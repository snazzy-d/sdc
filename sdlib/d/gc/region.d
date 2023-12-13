module d.gc.region;

import d.gc.allocclass;
import d.gc.base;
import d.gc.heap;
import d.gc.block;
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

struct RegionAllocator {
private:
	shared(Base)* base;

	import d.sync.mutex;
	Mutex mutex;

	uint dirtyBlockCount;

	// Free regions we can allocate from.
	ClassTree regionsByClass;
	RangeTree regionsByRange;

	// Unused region objects.
	Heap!(Region, unusedRegionCmp) unusedRegions;

	ulong minAddress = AddressSpace;
	ulong maxAddress = 0;

public:
	bool acquire(BlockDescriptor* block, uint extraBlocks = 0) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(RegionAllocator*) &this).acquireImpl(block, extraBlocks);
	}

	void release(BlockDescriptor* block) shared {
		// FIXME: assert the block is not borrowed.
		assert(block.empty, "Block is not empty!");

		release(block.address, 1);
	}

	void release(void* ptr, uint blocks) shared {
		assert(blocks > 0, "Invalid number of blocks!");

		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(RegionAllocator*) &this).releaseImpl(ptr, blocks);
	}

	auto computeAddressRange() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(RegionAllocator*) &this).computeAddressRangeImpl();
	}

private:
	auto computeAddressRangeImpl() {
		assert(mutex.isHeld(), "Mutex not held!");

		import d.gc.range;
		return AddressRange(cast(void*) minAddress, cast(void*) maxAddress);
	}

	bool acquireImpl(BlockDescriptor* block, uint extraBlocks = 0) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto totalBlocks = extraBlocks + 1;

		Region rr;
		rr.allocClass = getAllocClass(totalBlocks);

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
		block.at(ptr + extraSize);

		auto newBlockCount = r.blockCount - totalBlocks;
		if (newBlockCount == 0) {
			dirtyBlockCount -= r.dirtyBlockCount;
			unusedRegions.insert(r);
			return true;
		}

		// If we do not use the whole region, we need to keep track
		// of dirty blocks accurately.
		auto acquiredDirtyBlocks =
			r.countDirtyBlocksInSubRegion(0, totalBlocks);
		dirtyBlockCount -= acquiredDirtyBlocks;

		auto remainingDirtyBlocks = r.dirtyBlockCount - acquiredDirtyBlocks;
		auto allocSize = totalBlocks * BlockSize;
		r.at(ptr + allocSize, newBlockCount, remainingDirtyBlocks);
		registerRegion(r);

		return true;
	}

	void releaseImpl(void* ptr, uint blocks) {
		assert(mutex.isHeld(), "Mutex not held!");

		// Released blocks are considered dirty.
		dirtyBlockCount += blocks;

		auto r = getOrAllocateRegion();
		r.atDirty(ptr, blocks);
		registerRegion(r);
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
		return r.atClean(ptr, blocks & uint.max);
	}

	Region* getOrAllocateRegion() {
		auto r = unusedRegions.pop();
		if (r !is null) {
			return r;
		}

		auto slot = base.allocSlot();
		if (slot.address is null) {
			return null;
		}

		static assert(Region.sizeof <= ExtentSize, "Unexpected Region size!");
		return Region.fromSlot(slot);
	}
}

unittest acquire_release {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	// To snoop in.
	auto ra = cast(RegionAllocator*) &regionAllocator;

	BlockDescriptor block0;

	assert(ra.dirtyBlockCount == 0);
	assert(regionAllocator.acquire(&block0));

	// Check we compute the proper range.
	auto r = regionAllocator.computeAddressRange();
	assert(!r.contains(block0.address - 1));
	assert(r.contains(block0.address));
	assert(r.contains(block0.address + RefillBlockCount * BlockSize - 1));
	assert(!r.contains(block0.address + RefillBlockCount * BlockSize));

	foreach (i; 1 .. RefillBlockCount) {
		BlockDescriptor block;
		assert(regionAllocator.acquire(&block));
		assert(block.address is block0.address + i * BlockSize);
		assert(r.contains(block.address));
	}

	foreach (i; 5 .. RefillBlockCount) {
		BlockDescriptor block;
		block.at(block0.address + i * BlockSize);
		regionAllocator.release(&block);
		assert(ra.dirtyBlockCount == i - 4);
	}

	{
		auto r = ra.regionsByClass.extractAny();
		scope(exit) ra.regionsByClass.insert(r);

		assert(r.address is block0.address + 5 * BlockSize);
		assert(r.size == RefillSize - 5 * BlockSize);
	}

	foreach (i; 0 .. 5) {
		BlockDescriptor block;
		block.at(block0.address + i * BlockSize);
		regionAllocator.release(&block);
		assert(ra.dirtyBlockCount == i + 508);
	}

	{
		auto r = ra.regionsByClass.extractAny();
		scope(exit) ra.regionsByClass.insert(r);

		assert(r.address is block0.address);
		assert(r.size == RefillSize);
	}
}

unittest extra_blocks {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	BlockDescriptor block0;
	assert(regionAllocator.acquire(&block0));

	BlockDescriptor block1;
	assert(regionAllocator.acquire(&block1, 1));
	assert(block1.address is block0.address + 2 * BlockSize);

	BlockDescriptor block2;
	assert(regionAllocator.acquire(&block2, 5));
	assert(block2.address is block1.address + 6 * BlockSize);

	// Release 3 blocks. We now have 2 regions.
	assert(regionAllocator.dirtyBlockCount == 0);
	regionAllocator.release(&block0);
	assert(regionAllocator.dirtyBlockCount == 1);
	regionAllocator.release(block0.address + BlockSize, 2);
	assert(regionAllocator.dirtyBlockCount == 3);

	// Too big too fit.
	BlockDescriptor block3;
	assert(regionAllocator.acquire(&block3, 3));
	assert(block3.address is block2.address + 4 * BlockSize);
	assert(regionAllocator.dirtyBlockCount == 3);

	// Small enough, so we reuse freed regions.
	BlockDescriptor block4;
	assert(regionAllocator.acquire(&block4, 2));
	assert(block4.address is block0.address + 2 * BlockSize);
	assert(regionAllocator.dirtyBlockCount == 0);
}

unittest enormous {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	enum Blocks = 2048;
	enum ExtraBlocks = Blocks - 1;

	BlockDescriptor block0;
	assert(regionAllocator.acquire(&block0, ExtraBlocks));

	// Check we compute the proper range.
	auto r = regionAllocator.computeAddressRange();
	assert(!r.contains(block0.address - ExtraBlocks * BlockSize - 1));
	assert(r.contains(block0.address - ExtraBlocks * BlockSize));
	assert(r.contains(block0.address));
	assert(r.contains(block0.address + BlockSize - 1));
	assert(!r.contains(block0.address + BlockSize));

	regionAllocator.release(block0.address - ExtraBlocks * BlockSize, Blocks);
}

struct Region {
	void* address;
	uint blockCount;
	uint dirtyBlockCount;

	ubyte allocClass;
	ubyte generation;

	struct UsedLinks {
		ClassNode rbClass;
		RangeNode rbRange;
	}

	union Links {
		PHNode phnode;
		UsedLinks usedLinks;
	}

	Links _links;

	import d.gc.bitmap;
	Bitmap!RefillBlockCount dirtyBlocks;

	this(void* ptr, uint blockCount, ubyte generation = 0,
	     uint dirtyBlockCount = 0) {
		assert(isAligned(ptr, BlockSize), "Invalid ptr alignment!");
		assert(dirtyBlockCount <= blockCount,
		       "Dirty block count exceeds block count!");

		address = ptr;
		this.blockCount = blockCount;
		this.generation = generation;
		this.dirtyBlockCount = dirtyBlockCount;

		allocClass = getFreeSpaceClass(blockCount);
	}

public:
	Region* at(void* ptr, uint blockCount, uint dirtyBlockCount) {
		auto oldDirtyBlocks = dirtyBlocks;
		scope(success) dirtyBlocks = oldDirtyBlocks;

		this = Region(ptr, blockCount, generation, dirtyBlockCount);
		return &this;
	}

	Region* atClean(void* ptr, uint blockCount) {
		at(ptr, blockCount, 0);
		dirtyBlocks.clear();
		return &this;
	}

	Region* atDirty(void* ptr, uint blockCount) {
		at(ptr, blockCount, blockCount);

		// Make the region dirty.
		// FIXME: We use min to ensures we don't trip an assert
		// when the region is larger than 1GB.
		dirtyBlocks
			.setRollingRange(startOffset, min(blockCount, RefillBlockCount));

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

	uint countDirtyBlocksInSubRegion(uint start, uint length) {
		assert(start <= blockCount);
		assert(start + length <= blockCount);

		start = (start + startOffset) % RefillBlockCount;
		return dirtyBlocks.rollingCountBits(start, length);
	}

	Region* merge(Region* r) {
		assert(address is (r.address + r.size) || r.address is (address + size),
		       "Regions are not adjacent!");

		auto left = address < r.address ? &this : r;
		auto right = address < r.address ? r : &this;

		// Dirt is at all times contiguous within a region, and starts at the bottom.
		// Given as purging is not yet supported, this invariant always holds.
		assert(
			left.dirtyBlockCount == left.blockCount
				|| right.dirtyBlockCount == 0,
			"Merge would place dirty blocks in front of clean blocks!"
		);

		// Copy the dirty bits.
		// FIXME: We use min to ensures we don't trip an assert
		// when the region is larger than 1GB.
		dirtyBlocks.setRollingRangeFrom(r.dirtyBlocks, r.startOffset,
		                                min(r.blockCount, RefillBlockCount));

		auto a = min(address, r.address);
		return at(a, blockCount + r.blockCount,
		          dirtyBlockCount + r.dirtyBlockCount);
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
	static assert(LgAddressSpace <= 56, "Address space too large!");

	auto l = ulong(lhs.allocClass) << 56;
	auto r = ulong(rhs.allocClass) << 56;

	l |= cast(size_t) lhs.address;
	r |= cast(size_t) rhs.address;

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

unittest trackDirtyBlocks {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	// To snoop in.
	auto ra = cast(RegionAllocator*) &regionAllocator;

	BlockDescriptor[16] blockArray;
	void*[16] blockAddresses;

	foreach (i; 0 .. 16) {
		assert(regionAllocator.acquire(&blockArray[i]));
		blockAddresses[i] = blockArray[i].address;
	}

	void freeRun(BlockDescriptor[] blocks) {
		auto expectedDirtyBlocks = regionAllocator.dirtyBlockCount;

		foreach (b; blocks) {
			regionAllocator.release(&b);

			expectedDirtyBlocks++;
			assert(regionAllocator.dirtyBlockCount == expectedDirtyBlocks);

			Region rr;
			rr.at(b.address, 1, 0);
			auto r = ra.regionsByRange.find(&rr);
			assert(r.contains(b.address));
			assert(r.dirtyBlocks.valueAt(rr.startOffset));
		}
	}

	// Verify that a region with given block count and dirt exists at address.
	void verifyUniqueRegion(void* address, uint searchBlocks, uint blocks,
	                        uint dirtyBlocks) {
		Region rr;
		rr.allocClass = getAllocClass(searchBlocks);
		auto r = ra.regionsByClass.bestfit(&rr);
		assert(r !is null);
		assert(r.address == address);
		assert(r.blockCount == blocks);
		assert(r.dirtyBlockCount == dirtyBlocks);
		assert(r.countDirtyBlocksInSubRegion(0, blocks) == dirtyBlocks);
	}

	// Initially, there are no dirty blocks.
	assert(regionAllocator.dirtyBlockCount == 0);

	// Make some dirty regions.
	freeRun(blockArray[0 .. 2]);
	assert(regionAllocator.dirtyBlockCount == 2);
	verifyUniqueRegion(blockAddresses[0], 2, 2, 2);
	freeRun(blockArray[4 .. 8]);
	assert(regionAllocator.dirtyBlockCount == 6);
	verifyUniqueRegion(blockAddresses[4], 4, 4, 4);
	freeRun(blockArray[10 .. 15]);
	assert(regionAllocator.dirtyBlockCount == 11);
	verifyUniqueRegion(blockAddresses[10], 5, 5, 5);

	// Merge regions and confirm expected effect.
	freeRun(blockArray[8 .. 10]);
	assert(regionAllocator.dirtyBlockCount == 13);
	verifyUniqueRegion(blockAddresses[4], 10, 11, 11);
	freeRun(blockArray[2 .. 4]);
	assert(regionAllocator.dirtyBlockCount == 15);
	verifyUniqueRegion(blockAddresses[0], 14, 15, 15);
	freeRun(blockArray[15 .. 16]);
	verifyUniqueRegion(blockAddresses[0], 1, RefillBlockCount, 16);

	// Test dirt behaviour in acquire and release.
	BlockDescriptor block0;
	assert(regionAllocator.acquire(&block0, 5));
	assert(block0.address is blockAddresses[5]);
	assert(regionAllocator.dirtyBlockCount == 10);
	verifyUniqueRegion(blockAddresses[6], 1, RefillBlockCount - 6, 10);
	regionAllocator.release(blockAddresses[0], 6);
	assert(regionAllocator.dirtyBlockCount == 16);
	verifyUniqueRegion(blockAddresses[0], 1, RefillBlockCount, 16);
}
