module d.gc.region;

import d.gc.allocclass;
import d.gc.base;
import d.gc.heap;
import d.gc.range;
import d.gc.rbtree;

import d.gc.spec;
import d.gc.util;

import sdc.intrinsics;

alias ClassTree = RBTree!(Region, classAddrRegionCmp, "rbClass");
alias RangeTree = RBTree!(Region, addrRangeRegionCmp, "rbRange");

alias ClassNode = rbtree.Node!(Region, "rbClass");
alias RangeNode = rbtree.Node!(Region, "rbRange");
alias PHNode = heap.Node!Region;

// Reserve memory in blocks of 1GB.
enum RefillSize = 1024 * 1024 * 1024;
enum uint RefillBlockCount = RefillSize / BlockSize;

static assert(RefillBlockCount == 512);

@property
shared(RegionAllocator)* gDataRegionAllocator() {
	static shared RegionAllocator regionAllocator;

	if (unlikely(regionAllocator.base is null)) {
		regionAllocator.base = &gBase;
	}

	return &regionAllocator;
}

@property
shared(RegionAllocator)* gPointerRegionAllocator() {
	static shared RegionAllocator regionAllocator;

	if (unlikely(regionAllocator.base is null)) {
		regionAllocator.base = &gBase;
	}

	return &regionAllocator;
}

enum MinimumBlockCollectThreshold = 8;

struct RegionAllocator {
private:
	shared(Base)* base;

	import d.sync.mutex;
	Mutex mutex;

	// Free regions we can allocate from.
	ClassTree regionsByClass;
	RangeTree regionsByRange;

	// Unused region objects.
	Heap!(Region, unusedRegionCmp) unusedRegions;

	size_t minAddress = AddressSpace;
	size_t maxAddress = 0;

	// Count of blocks that are currently acquired.
	size_t nBlocks;

	// Threshold at which a collection should be run.
	size_t blockCollectThreshold = MinimumBlockCollectThreshold;
public:
	bool acquire(void** addrPtr, uint extraBlocks = 0) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(RegionAllocator*) &this).acquireImpl(addrPtr, extraBlocks);
	}

	void release(void* ptr, uint blocks) shared {
		assert(blocks > 0, "Invalid number of blocks!");

		// Eagerly clean the block we are returned.
		import d.gc.memmap;
		pages_purge(ptr, blocks * BlockSize);

		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(RegionAllocator*) &this).releaseImpl(ptr, blocks);
	}

	auto computeAddressRange() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(RegionAllocator*) &this).computeAddressRangeImpl();
	}

	bool checkBlockThreshold() shared {
		return nBlocks >= blockCollectThreshold;
	}

	void setBlockThreshold(int targetNum, int targetDen) shared {
		blockCollectThreshold =
			max(nBlocks * targetNum / targetDen, MinimumBlockCollectThreshold);
	}

private:
	auto computeAddressRangeImpl() {
		assert(mutex.isHeld(), "Mutex not held!");

		return makeRange(cast(void*) minAddress, cast(void*) maxAddress);
	}

	bool acquireImpl(void** addrPtr, uint extraBlocks) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto totalBlocks = extraBlocks + 1;

		Region rr;
		rr.setAllocClass(getAllocClass(totalBlocks));

		auto r = regionsByClass.extractBestFit(&rr);
		if (r is null) {
			r = refillAddressSpace(extraBlocks);
			if (r is null) {
				return false;
			}
		} else {
			regionsByRange.remove(r);
		}

		assert(r.address !is null && isAligned(r.address, BlockSize),
		       "Invalid address!");
		assert(r.blockCount > extraBlocks, "Insuffiscient address space!");

		auto ptr = r.address;
		auto extraSize = extraBlocks * BlockSize;
		*addrPtr = ptr + extraSize;

		nBlocks += totalBlocks;

		auto newBlockCount = r.blockCount - totalBlocks;
		if (newBlockCount == 0) {
			unusedRegions.insert(r);
			return true;
		}

		auto allocSize = totalBlocks * BlockSize;
		r.at(ptr + allocSize, newBlockCount);
		registerRegion(r);

		return true;
	}

	void releaseImpl(void* ptr, uint blocks) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto r = getOrAllocateRegion();
		r.at(ptr, blocks);
		registerRegion(r);

		nBlocks -= blocks;
	}

	void registerRegion(Region* r) {
		assert(r !is null, "Region is null!");

		// First, merge adjacent ranges.
		while (true) {
			auto adjacent = regionsByRange.extract(r);
			if (adjacent is null) {
				break;
			}

			regionsByClass.remove(adjacent);

			// Make sure we keep using the best region.
			bool needSwap = unusedRegionCmp(r, adjacent) < 0;
			auto m = needSwap ? r : adjacent;
			r = needSwap ? adjacent : r;

			r.merge(m);
			unusedRegions.insert(m);
		}

		regionsByClass.insert(r);
		regionsByRange.insert(r);
	}

	Region* refillAddressSpace(uint extraBlocks) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto r = getOrAllocateRegion();
		if (r is null) {
			return null;
		}

		auto blocks = alignUp(extraBlocks + 1, RefillBlockCount);
		auto size = blocks * BlockSize;

		auto ptr = base.reserveAddressSpace(size, BlockSize);
		if (ptr is null) {
			unusedRegions.insert(r);
			return null;
		}

		auto v = cast(size_t) ptr;
		minAddress = min(minAddress, v);
		maxAddress = max(maxAddress, v + blocks * BlockSize);

		// Newly allocated blocks are considered clean.
		assert(blocks <= uint.max, "blocks does not fit in 32 bits!");
		return r.at(ptr, blocks & uint.max);
	}

	Region* getOrAllocateRegion() {
		auto r = unusedRegions.pop();
		if (r !is null) {
			return r;
		}

		static assert(ExtentSize / Region.sizeof == 2,
		              "Unexpected Region size!");

		auto slot = base.allocSlot();
		if (slot.address is null) {
			return null;
		}

		auto r0 = cast(Region*) slot.address;
		*r0 = Region(null, 0, slot.generation);

		auto r1 = r0 + 1;
		*r1 = Region(null, 0, slot.generation);

		unusedRegions.insert(r1);
		return r0;
	}
}

unittest acquire_release {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	// To snoop in.
	auto ra = cast(RegionAllocator*) &regionAllocator;

	void* addr0;
	assert(regionAllocator.acquire(&addr0));

	// check the block counter works
	assert(regionAllocator.nBlocks == 1);

	// Check we compute the proper range.
	auto r = regionAllocator.computeAddressRange();
	assert(!r.contains(addr0 - 1));
	assert(r.contains(addr0));
	assert(r.contains(addr0 + RefillBlockCount * BlockSize - 1));
	assert(!r.contains(addr0 + RefillBlockCount * BlockSize));

	bool passedThreshold = false;
	foreach (i; 1 .. RefillBlockCount) {
		void* addr;
		assert(regionAllocator.acquire(&addr));
		assert(addr is addr0 + i * BlockSize);
		assert(r.contains(addr));
		assert(regionAllocator.nBlocks == i + 1);
		if (!passedThreshold && regionAllocator.checkBlockThreshold()) {
			passedThreshold = true;
			assert(regionAllocator.nBlocks == MinimumBlockCollectThreshold);
		}
	}

	assert(regionAllocator.checkBlockThreshold());

	foreach (i; 5 .. RefillBlockCount) {
		void* addr = addr0 + i * BlockSize;
		regionAllocator.release(addr, 1);
	}

	assert(regionAllocator.nBlocks == 5);
	assert(!regionAllocator.checkBlockThreshold());
	// this should trigger the min threshold which should be 8 blocks.
	regionAllocator.setBlockThreshold(1, 1);

	assert(!regionAllocator.checkBlockThreshold());

	{
		auto r = ra.regionsByClass.extractAny();
		scope(exit) ra.regionsByClass.insert(r);

		assert(r.address is addr0 + 5 * BlockSize);
		assert(r.size == RefillSize - 5 * BlockSize);
	}

	foreach (i; 0 .. 5) {
		void* addr = addr0 + i * BlockSize;
		regionAllocator.release(addr, 1);
	}

	{
		auto r = ra.regionsByClass.extractAny();
		scope(exit) ra.regionsByClass.insert(r);

		assert(r.address is addr0);
		assert(r.size == RefillSize);
	}
}

unittest extra_blocks {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	void* addr0;
	assert(regionAllocator.acquire(&addr0));

	void* addr1;
	assert(regionAllocator.acquire(&addr1, 1));
	assert(addr1 is addr0 + 2 * BlockSize);
	assert(regionAllocator.nBlocks == 1 + 2);

	void* addr2;
	assert(regionAllocator.acquire(&addr2, 5));
	assert(addr2 is addr1 + 6 * BlockSize);
	assert(regionAllocator.nBlocks == 1 + 2 + 6);

	// Release 3 blocks. We now have 2 regions.
	regionAllocator.release(addr0, 1);
	regionAllocator.release(addr0 + BlockSize, 2);
	assert(regionAllocator.nBlocks == 6);

	// Too big too fit.
	void* addr3;
	assert(regionAllocator.acquire(&addr3, 3));
	assert(addr3 is addr2 + 4 * BlockSize);
	assert(regionAllocator.nBlocks == 6 + 4);

	// Small enough, so we reuse freed regions.
	void* addr4;
	assert(regionAllocator.acquire(&addr4, 2));
	assert(addr4 is addr0 + 2 * BlockSize);
	assert(regionAllocator.nBlocks == 6 + 4 + 3);
}

unittest enormous {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	enum Blocks = 2048;
	enum ExtraBlocks = Blocks - 1;

	void* addr0;
	assert(regionAllocator.acquire(&addr0, ExtraBlocks));

	// Check we compute the proper range.
	auto r = regionAllocator.computeAddressRange();
	assert(!r.contains(addr0 - ExtraBlocks * BlockSize - 1));
	assert(r.contains(addr0 - ExtraBlocks * BlockSize));
	assert(r.contains(addr0));
	assert(r.contains(addr0 + BlockSize - 1));
	assert(!r.contains(addr0 + BlockSize));

	regionAllocator.release(addr0 - ExtraBlocks * BlockSize, Blocks);
}

struct Region {
	/**
	 * This is a bitfield containing the following elements:
	 *  - c: The alloc class.
	 *  - a: The address (BlockSize-aligned)
	 *  - g: The generation.
	 * 
	 * 63    56 55    48 47    40 39    32 31    24 23    16 15     8 7      0
	 * cccccccc ........ aaaaaaaa aaaaaaaa aaaaaaaa aaa..... ........ gggggggg
	 */
	ulong bits;

	// Verify our assumptions.
	static assert(LgAddressSpace <= 56, "Address space too large!");
	static assert(LgBlockSize >= 8, "Not enough space in low bits!");

	// Useful constants for bit manipulations.
	enum AllocClassIndex = 56;

	uint blockCount;

	struct UsedLinks {
		ClassNode rbClass;
		RangeNode rbRange;
	}

	union Links {
		PHNode phnode;
		UsedLinks usedLinks;
	}

	Links _links;

	this(void* ptr, uint blockCount, ubyte generation = 0) {
		assert(isAligned(ptr, BlockSize), "Invalid ptr alignment!");

		bits = generation | cast(size_t) ptr;
		bits |= ulong(getFreeSpaceClass(blockCount)) << AllocClassIndex;

		this.blockCount = blockCount;
	}

public:
	Region* at(void* ptr, uint blockCount) {
		this = Region(ptr, blockCount, generation);
		return &this;
	}

	static fromSlot(GenerationPointer slot) {
		// FIXME: in contract
		assert(slot.address !is null, "Slot is empty!");

		auto r = (cast(Region*) slot.address);
		*r = Region(null, 0, slot.generation);
		return r;
	}

	@property
	void* address() const {
		return cast(void*) (bits & BlockPointerMask);
	}

	@property
	ubyte allocClass() {
		return bits >> AllocClassIndex;
	}

	void setAllocClass(ubyte c) {
		enum Mask = (size_t(1) << AllocClassIndex) - 1;
		bits &= Mask;
		bits |= ulong(c) << AllocClassIndex;
	}

	@property
	ubyte generation() {
		return bits & ubyte.max;
	}

	@property
	ref PHNode phnode() {
		return _links.phnode;
	}

	@property
	ref ClassNode rbClass() {
		return _links.usedLinks.rbClass;
	}

	@property
	ref RangeNode rbRange() {
		return _links.usedLinks.rbRange;
	}

	@property
	size_t size() const {
		return blockCount * BlockSize;
	}

	@property
	uint startOffset() const {
		auto blockIndex = (cast(size_t) address) / BlockSize;
		return blockIndex % RefillBlockCount;
	}

	bool contains(const void* ptr) const {
		return address <= ptr && ptr < address + size;
	}

	Region* merge(Region* r) {
		assert(address is (r.address + r.size) || r.address is (address + size),
		       "Regions are not adjacent!");

		auto a = min(address, r.address);
		return at(a, blockCount + r.blockCount);
	}
}

ptrdiff_t addrRangeRegionCmp(Region* lhs, Region* rhs) {
	auto lstart = cast(size_t) lhs.address;
	auto rstart = cast(size_t) rhs.address;

	auto lend = lstart + lhs.size;
	auto rend = rstart + rhs.size;

	return (lstart > rend) - (lend < rstart);
}

unittest rangeTree {
	import d.gc.rbtree;
	RBTree!(Region, addrRangeRegionCmp, "rbRange") regionsByRange;

	auto base = cast(void*) 0x456789a00000;
	auto r0 = Region(base, 1);
	auto r1 = Region(base + BlockSize, 1);
	auto r2 = Region(base + 2 * BlockSize, 1);

	regionsByRange.insert(&r0);

	assert(regionsByRange.extract(&r2) is null);
	regionsByRange.insert(&r2);

	assert(regionsByRange.extract(&r1) is &r0);
	assert(regionsByRange.extract(&r1) is &r2);
	assert(regionsByRange.extract(&r1) is null);
}

ptrdiff_t classAddrRegionCmp(Region* lhs, Region* rhs) {
	auto l = lhs.bits;
	auto r = rhs.bits;

	return (l > r) - (l < r);
}

ptrdiff_t unusedRegionCmp(Region* lhs, Region* rhs) {
	static assert(LgAddressSpace <= 56, "Address space too large!");

	auto l = ulong(lhs.generation) << 56;
	auto r = ulong(rhs.generation) << 56;

	l |= cast(size_t) lhs;
	r |= cast(size_t) rhs;

	return (l > r) - (l < r);
}
