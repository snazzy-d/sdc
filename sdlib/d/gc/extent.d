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

	@property
	bool dense() const {
		enum Sieve = 1 << 0 | 1 << 16 | 1 << 20 | 1 << 22;
		auto match = Sieve & (1 << data);
		return !match && data < 24;
	}

	@property
	bool sparse() const {
		return !dense;
	}

	@property
	bool supportsMetadata() const {
		return data != 1;
	}

	@property
	bool supportsInlineMarking() const {
		return uint(data - 1) > 2;
	}
}

unittest ExtentClass {
	auto l = ExtentClass.large();
	assert(!l.isSlab());
	assert(!l.dense);
	assert(l.sparse);
	assert(l.supportsMetadata);
	assert(l.supportsInlineMarking);

	foreach (ubyte sc; 0 .. ClassCount.Small) {
		auto s = ExtentClass.slab(sc);
		assert(s.isSlab());
		assert(s.sizeClass == sc);

		assert(s.dense == isDenseSizeClass(sc));
		assert(s.sparse == isSparseSizeClass(sc));
		assert(s.supportsMetadata == sizeClassSupportsMetadata(sc));
		assert(s.supportsInlineMarking == sizeClassSupportsInlineMarking(sc));
	}
}

struct Extent {
private:
	/**
	 * This is a bitfield containing the following elements:
	 *  - n: The number of free slots.
	 *  - p: The address of the memory managed by Extent.
	 *  - a: The arena index.
	 * 
	 * 63    56 55    48 47    40 39    32 31    24 23    16 15     8 7      0
	 * nnnnnnnn nnnnnnnn pppppppp pppppppp pppppppp pppppppp ppppaaaa aaaaaaaa
	 */
	ulong bits;

	// Verify our assumptions.
	static assert(LgAddressSpace <= 48, "Address space too large!");
	static assert(LgPageSize >= LgArenaCount, "Not enough space in low bits!");

	// Useful constants for bit manipulations.
	enum FreeSlotsIndex = 48;
	enum FreeSlotsUnit = 1UL << FreeSlotsIndex;

public:
	uint _npages;
	ExtentClass extentClass;
	ubyte generation;

	import d.gc.block;
	BlockDescriptor* block;

private:
	Node!Extent _phnode;

	// TODO: Reuse this data to do something useful,
	// like garbage collection :P
	void* _pad0;
	void* _pad1;

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

	this(uint arenaIndex, void* ptr, uint npages, ubyte generation,
	     BlockDescriptor* block, ExtentClass extentClass) {
		// FIXME: in contract.
		assert((arenaIndex & ~ArenaMask) == 0, "Invalid arena index!");
		assert(isAligned(ptr, PageSize), "Invalid alignment!");

		this.bits = arenaIndex | cast(size_t) ptr;

		this._npages = npages;
		this.extentClass = extentClass;
		this.generation = generation;
		this.block = block;

		if (extentClass.isSlab()) {
			import d.gc.slab;
			bits |= ulong(binInfos[sizeClass].nslots) << FreeSlotsIndex;

			slabData.clear();
		} else {
			setUsedCapacity(size);
			setFinalizer(null);
		}
	}

public:
	Extent* at(void* ptr, uint npages, BlockDescriptor* block,
	           ExtentClass extentClass) {
		this = Extent(arenaIndex, ptr, npages, generation, block, extentClass);
		return &this;
	}

	Extent* at(void* ptr, uint npages, BlockDescriptor* block) {
		return at(ptr, npages, block, ExtentClass.large());
	}

	static fromSlot(uint arenaIndex, GenerationPointer slot) {
		// FIXME: in contract
		assert((arenaIndex & ~ArenaMask) == 0, "Invalid arena index!");
		assert(slot.address !is null, "Slot is empty!");
		assert(isAligned(slot.address, ExtentAlign),
		       "Invalid slot alignement!");

		auto e = cast(Extent*) slot.address;
		e.bits = arenaIndex;
		e.generation = slot.generation;

		return e;
	}

	@property
	void* address() const {
		return cast(void*) (bits & PagePointerMask);
	}

	@property
	size_t size() const {
		return npages * PageSize;
	}

	@property
	uint npages() const {
		return _npages;
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
		return bits & ArenaMask;
	}

	@property
	bool containsPointers() const {
		return (arenaIndex & 0x01) != 0;
	}

	/**
	 * Slab features.
	 */
	bool isSlab() const {
		return extentClass.isSlab();
	}

	@property
	ubyte sizeClass() const {
		return extentClass.sizeClass;
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
		return (bits >> FreeSlotsIndex) & Mask;
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

		scope(success) bits -= count * FreeSlotsUnit;
		return count;
	}

	void free(uint index) {
		// FIXME: in contract.
		assert(isSlab(), "free accessed on non slab!");
		assert(slabData.valueAt(index), "Slot is already free!");

		bits += FreeSlotsUnit;
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

alias PriorityExtentHeap = Heap!(Extent, priorityExtentCmp);

ptrdiff_t priorityExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = lhs.bits;
	auto r = rhs.bits;

	return (l > r) - (l < r);
}

unittest priority {
	static makeExtent(void* address, uint nalloc) {
		Extent e;
		e.at(address, 1, null, ExtentClass.slab(0));
		e.bits -= nalloc * Extent.FreeSlotsUnit;

		assert(e.address is address);
		assert(e.nfree == (512 - nalloc));
		return e;
	}

	PriorityExtentHeap heap;
	assert(heap.top is null);

	auto minPtr = cast(void*) PageSize;
	auto midPtr = cast(void*) BlockSize;
	auto maxPtr = cast(void*) (AddressSpace - PageSize);

	// Lowest priority slab possible.
	auto e0 = makeExtent(maxPtr, 0);
	heap.insert(&e0);
	assert(heap.top is &e0);

	// Lower address is better.
	auto e1 = makeExtent(null, 0);
	heap.insert(&e1);
	assert(heap.top is &e1);

	// But more allocations is even better!
	auto e2 = makeExtent(maxPtr, 500);
	heap.insert(&e2);
	assert(heap.top is &e2);

	// Lower address remains a tie breaker.
	auto e3 = makeExtent(null, 500);
	heap.insert(&e3);
	assert(heap.top is &e3);

	// Try inserting a few blocks out of order.
	auto e4 = makeExtent(midPtr + PageSize, 500);
	auto e5 = makeExtent(maxPtr - PageSize, 250);
	auto e6 = makeExtent(midPtr, 250);
	auto e7 = makeExtent(midPtr, 400);
	heap.insert(&e4);
	heap.insert(&e5);
	heap.insert(&e6);
	heap.insert(&e7);

	// Pop all the blocks and check they come out in
	// the expected order.
	assert(heap.pop() is &e3);
	assert(heap.pop() is &e4);
	assert(heap.pop() is &e2);
	assert(heap.pop() is &e7);
	assert(heap.pop() is &e6);
	assert(heap.pop() is &e5);
	assert(heap.pop() is &e1);
	assert(heap.pop() is &e0);
	assert(heap.pop() is null);
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
	enum Pages = 13;
	enum Size = Pages * PageSize;

	Extent e;
	e.at(base, Pages, null);

	assert(!e.contains(base - 1));
	assert(!e.contains(base + Size));

	foreach (i; 0 .. Size) {
		assert(e.contains(base + i));
	}
}

unittest allocfree {
	Extent e;
	e.at(null, 1, null, ExtentClass.slab(0));

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
	e.at(null, 1, null, ExtentClass.slab(0));

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
