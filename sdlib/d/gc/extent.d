module d.gc.extent;

import d.gc.base;
import d.gc.bitmap;
import d.gc.heap;
import d.gc.sizeclass;
import d.gc.spec;
import d.gc.util;

struct ExtentClass {
	ubyte data;

	this(ubyte data) {
		this.data = data;
	}

	enum Mask = (1 << 6) - 1;

	import d.gc.sizeclass;
	static assert((ClassCount.Small & ~Mask) == 0,
	              "ExtentClass doesn't fit on 6 bits!");

	static large() {
		return ExtentClass(0);
	}

	static slab(ubyte sizeClass) {
		// FIXME: in contract.
		assert(sizeClass < ClassCount.Small, "Invalid size class!");

		sizeClass += 1;
		return ExtentClass(sizeClass);
	}

	bool isSlab() const {
		return data != 0;
	}

	@property
	ubyte sizeClass() const {
		// FIXME: in contract.
		assert(isSlab(), "Non slab do not have a size class!");
		return (data - 1) & ubyte.max;
	}
}

unittest ExtentClass {
	auto l = ExtentClass.large();
	assert(!l.isSlab());

	auto s0 = ExtentClass.slab(0);
	assert(s0.isSlab());
	assert(s0.sizeClass == 0);

	auto s9 = ExtentClass.slab(9);
	assert(s9.isSlab());
	assert(s9.sizeClass == 9);

	auto smax = ExtentClass.slab(ClassCount.Small - 1);
	assert(smax.isSlab());
	assert(smax.sizeClass == ClassCount.Small - 1);
}

struct Extent {
private:
	/**
	 * This is a bitfield containing the following elements:
	 *  - e: The extent class.
	 *  - a: The arena index.
	 *  - n: The number of free slots.
	 * 
	 * 63    56 55    48 47    40 39    32 31    24 23    16 15     8 7      0
	 * nnnnnnnn nnnnnnnn ....aaaa aaaaaaaa ........ ........ ........ ..eeeeee
	 */
	ulong bits;

public:
	void* address;
	size_t sizeAndGen;

	import d.gc.block;
	BlockDescriptor* block;

private:
	// TODO: Reuse this data to do something useful,
	// like garbage collection :P
	void* _pad;

	Node!Extent _phnode;

	struct SlabMetadata {
		ubyte[32] pad;
		shared Bitmap!256 slabMetadataFlags;
	}

	union Bitmaps {
		Bitmap!512 slabData;
		SlabMetadata slabMetadata;
	}

	struct LargeData {
		// Metadata for large extents.
		size_t usedCapacity;

		// Optional finalizer.
		Finalizer finalizer;
	}

	union Metadata {
		// Slab occupancy (and metadata flags for supported size classes)
		Bitmaps slabData;

		// Metadata for large extents.
		LargeData largeData;
	}

	Metadata _metadata;

	this(uint arenaIndex, void* ptr, size_t size, ubyte generation,
	     BlockDescriptor* block, ExtentClass ec) {
		// FIXME: in contract.
		assert((arenaIndex & ~ArenaMask) == 0, "Invalid arena index!");
		assert(isAligned(ptr, PageSize), "Invalid alignment!");
		assert(isAligned(size, PageSize), "Invalid size!");

		this.address = ptr;
		this.sizeAndGen = size | generation;
		this.block = block;

		bits = ec.data;
		bits |= ulong(arenaIndex) << 32;

		if (ec.isSlab()) {
			import d.gc.slab;
			bits |= ulong(binInfos[ec.sizeClass].nslots) << 48;

			slabData.clear();
		} else {
			setUsedCapacity(size);
			setFinalizer(null);
		}
	}

public:
	Extent* at(void* ptr, size_t size, BlockDescriptor* block, ExtentClass ec) {
		this = Extent(arenaIndex, ptr, size, generation, block, ec);
		return &this;
	}

	Extent* at(void* ptr, size_t size, BlockDescriptor* block) {
		return at(ptr, size, block, ExtentClass.large());
	}

	static fromSlot(uint arenaIndex, GenerationPointer slot) {
		// FIXME: in contract
		assert((arenaIndex & ~ArenaMask) == 0, "Invalid arena index!");
		assert(slot.address !is null, "Slot is empty!");
		assert(isAligned(slot.address, ExtentAlign),
		       "Invalid slot alignement!");

		auto e = cast(Extent*) slot.address;
		e.bits = ulong(arenaIndex) << 32;
		e.sizeAndGen = slot.generation;

		return e;
	}

	@property
	size_t size() const {
		return sizeAndGen & ~PageMask;
	}

	@property
	uint pageCount() const {
		auto pc = sizeAndGen / PageSize;

		assert(pc == pc & uint.max, "Invalid page count!");
		return pc & uint.max;
	}

	bool isHuge() const {
		import d.gc.size;
		return size >= MaxLargeSize;
	}

	@property
	uint blockIndex() const {
		assert(isHuge() || block.address is alignDown(address, BlockSize));
		assert(!isHuge() || isAligned(address, BlockSize));

		return ((cast(size_t) address) / PageSize) % PagesInBlock;
	}

	@property
	ubyte generation() const {
		return sizeAndGen & 0xff;
	}

	@property
	ref Node!Extent phnode() {
		return _phnode;
	}

	bool contains(void* ptr) const {
		return ptr >= address && ptr < address + size;
	}

	/**
	 * Arena.
	 */
	@property
	uint arenaIndex() const {
		return (bits >> 32) & ArenaMask;
	}

	@property
	bool containsPointers() const {
		return (arenaIndex & 0x01) != 0;
	}

	/**
	 * Slab features.
	 */
	@property
	auto extentClass() const {
		return ExtentClass(bits & ExtentClass.Mask);
	}

	bool isSlab() const {
		auto ec = extentClass;
		return ec.isSlab();
	}

	@property
	ubyte sizeClass() const {
		auto ec = extentClass;
		return ec.sizeClass;
	}

	@property
	uint nslots() const {
		assert(isSlab(), "nslots accessed on non slab!");

		import d.gc.slab;
		return binInfos[sizeClass].nslots;
	}

	@property
	uint nfree() const {
		// FIXME: in contract.
		assert(isSlab(), "nfree accessed on non slab!");

		enum Mask = (1 << 10) - 1;
		return (bits >> 48) & Mask;
	}

	uint batchAllocate(void*[] buffer, size_t slotSize) {
		// FIXME: in contract.
		assert(isSlab(), "allocate accessed on non slab!");
		assert(nfree > 0, "Slab is full!");

		void** insert = buffer.ptr;
		uint count = min(buffer.length, nfree) & uint.max;

		uint total = 0;
		uint n = -1;
		ulong nimble = 0;
		ulong current = 0;

		while (total < count) {
			while (current == 0) {
				nimble = slabData.rawContent[++n];
				current = ~nimble;
			}

			enum NimbleSize = 8 * ulong.sizeof;
			auto shift = n * NimbleSize;

			import sdc.intrinsics;
			uint nCount = min(popCount(current), count) & uint.max;

			foreach (_; 0 .. nCount) {
				import sdc.intrinsics;
				auto bit = countTrailingZeros(current);
				current ^= 1UL << bit;

				auto slot = shift + bit;
				*(insert++) = address + slot * slotSize;
			}

			slabData.rawContent[n] = ~current;
			total += nCount;
		}

		scope(success) bits -= ulong(count) << 48;
		return count;
	}

	void free(uint index) {
		// FIXME: in contract.
		assert(isSlab(), "free accessed on non slab!");
		assert(slabData.valueAt(index), "Slot is already free!");

		bits += (1UL << 48);
		slabData.clearBit(index);
	}

	/**
	 * Metadata features for slabs.
	 */
	@property
	ref Bitmap!512 slabData() {
		// FIXME: in contract.
		assert(isSlab(), "slabData accessed on non slab!");

		return _metadata.slabData.slabData;
	}

	@property
	ref shared(Bitmap!256) slabMetadataFlags() {
		assert(isSlab(), "slabMetadataFlags accessed on non slab!");
		assert(sizeClassSupportsMetadata(sizeClass),
		       "size class not supports slab metadata!");

		return _metadata.slabData.slabMetadata.slabMetadataFlags;
	}

	bool hasMetadata(uint index) {
		assert(isSlab(), "hasMetadata accessed on non slab!");
		assert(sizeClassSupportsMetadata(sizeClass),
		       "size class not supports slab metadata!");
		assert(index < nslots, "index is out of range!");

		return slabMetadataFlags.valueAtAtomic(index);
	}

	void enableMetadata(uint index) {
		assert(isSlab(), "hasMetadata accessed on non slab!");
		assert(sizeClassSupportsMetadata(sizeClass),
		       "size class not supports slab metadata!");
		assert(index < nslots, "index is out of range!");

		slabMetadataFlags.setBitAtomic(index);
	}

	void disableMetadata(uint index) {
		assert(isSlab(), "hasMetadata accessed on non slab!");
		assert(sizeClassSupportsMetadata(sizeClass),
		       "size class not supports slab metadata!");
		assert(index < nslots, "index is out of range!");

		slabMetadataFlags.clearBitAtomic(index);
	}

	/**
	 * Large features.
	 */
	bool isLarge() const {
		return !isSlab();
	}

	@property
	size_t usedCapacity() {
		assert(isLarge(), "usedCapacity accessed on non large!");
		return _metadata.largeData.usedCapacity;
	}

	void setUsedCapacity(size_t size) {
		assert(isLarge(), "Cannot set used capacity on a slab alloc!");
		_metadata.largeData.usedCapacity = size;
	}

	@property
	Finalizer finalizer() {
		assert(isLarge(), "Finalizer accessed on non large!");
		return _metadata.largeData.finalizer;
	}

	void setFinalizer(Finalizer finalizer) {
		assert(isLarge(), "Cannot set finalizer on a slab alloc!");
		_metadata.largeData.finalizer = finalizer;
	}
}

unittest finalizers {
	static void destruct(void* ptr, size_t size) {}

	// Basic test for large allocs:
	import d.gc.tcache;
	auto large = threadCache.alloc(20000, false);
	auto largePd = threadCache.getPageDescriptor(large);
	largePd.extent.setUsedCapacity(19999);
	assert(largePd.extent.finalizer is null);
	largePd.extent.setFinalizer(&destruct);
	assert(cast(void*) largePd.extent.finalizer == cast(void*) &destruct);
	assert(largePd.extent.usedCapacity == 19999);
	threadCache.free(large);
}

static assert(Extent.sizeof == ExtentSize, "Unexpected Extent size!");
static assert(Extent.sizeof == ExtentAlign, "Unexpected Extent alignment!");

alias AddrExtentHeap = Heap!(Extent, addrExtentCmp);

ptrdiff_t addrExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs.address;
	auto r = cast(size_t) rhs.address;

	// We need to compare that way to avoid integer overflow.
	return (l > r) - (l < r);
}

alias UnusedExtentHeap = Heap!(Extent, unusedExtentCmp);

ptrdiff_t unusedExtentCmp(Extent* lhs, Extent* rhs) {
	static assert(LgAddressSpace <= 56, "Address space too large!");

	auto l = ulong(lhs.generation) << 56;
	auto r = ulong(rhs.generation) << 56;

	l |= cast(size_t) lhs;
	r |= cast(size_t) rhs;

	return (l > r) - (l < r);
}

unittest contains {
	auto base = cast(void*) 0x56789abcd000;
	enum Size = 13 * PageSize;

	Extent e;
	e.address = base;
	e.sizeAndGen = Size;

	assert(!e.contains(base - 1));
	assert(!e.contains(base + Size));

	foreach (i; 0 .. Size) {
		assert(e.contains(base + i));
	}
}

unittest allocfree {
	Extent e;
	e.at(null, PageSize, null, ExtentClass.slab(0));

	static checkAllocate(ref Extent e, uint index) {
		void*[1] buffer;
		assert(e.batchAllocate(buffer[0 .. 1], PointerSize) == 1);

		auto expected = index * PointerSize;
		auto provided = cast(size_t) buffer[0];

		assert(provided == expected);
	}

	assert(e.isSlab());
	assert(e.sizeClass == 0);
	assert(e.nfree == 512);

	checkAllocate(e, 0);
	assert(e.nfree == 511);

	checkAllocate(e, 1);
	assert(e.nfree == 510);

	checkAllocate(e, 2);
	assert(e.nfree == 509);

	e.free(1);
	assert(e.nfree == 510);

	checkAllocate(e, 1);
	assert(e.nfree == 509);

	checkAllocate(e, 3);
	assert(e.nfree == 508);

	e.free(0);
	e.free(3);
	e.free(2);
	e.free(1);
	assert(e.nfree == 512);
}

unittest batchAllocate {
	Extent e;
	e.at(null, PageSize, null, ExtentClass.slab(0));

	void*[1024] buffer;
	assert(e.batchAllocate(buffer[0 .. 1024], PointerSize) == 512);
	assert(e.nfree == 0);

	foreach (i; 0 .. 512) {
		assert(i * PointerSize == cast(size_t) buffer[i]);
	}

	// Free half the elements.
	foreach (i; 0 .. 256) {
		e.free(2 * i);
	}

	assert(e.nfree == 256);
	assert(e.batchAllocate(buffer[512 .. 1024], PointerSize) == 256);
	assert(e.nfree == 0);

	foreach (i; 0 .. 256) {
		assert(2 * i * PointerSize == cast(size_t) buffer[512 + i]);
	}

	// Free All the element but two in the middle
	foreach (i; 0 .. 255) {
		e.free(i);
		e.free(511 - i);
	}

	assert(e.nfree == 510);
	assert(e.batchAllocate(buffer[0 .. 500], PointerSize) == 500);
	assert(e.nfree == 10);

	foreach (i; 0 .. 255) {
		assert(i * PointerSize == cast(size_t) buffer[i]);
	}

	foreach (i; 0 .. 245) {
		assert((i + 257) * PointerSize == cast(size_t) buffer[255 + i]);
	}
}
