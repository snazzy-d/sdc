module d.gc.arena;

import d.gc.allocclass;
import d.gc.emap;
import d.gc.extent;
import d.gc.block;
import d.gc.size;
import d.gc.sizeclass;
import d.gc.spec;
import d.gc.util;

import sdc.intrinsics;

struct Arena {
private:
	ulong bits;

	import d.gc.bin;
	Bin[ClassCount.Small] bins;

	import d.sync.mutex;
	Mutex mutex;

	UnusedExtentHeap unusedExtents;

	enum HeapCount = getAllocClass(PagesInBlock - 1);
	static assert(HeapCount <= 32, "Too many heaps to fit in the filter!");

	uint filter;
	PriorityBlockHeap[HeapCount] heaps;

	import d.gc.ring;
	Ring!BlockDescriptor fullBlocks;

	UnusedBlockHeap unusedBlockDescriptors;
	AllBlockRing allBlocks;

	import d.gc.base;
	Base base;

	import d.gc.region;
	shared(RegionAllocator)* regionAllocator;

	enum InitializedBit = 1UL << 63;

	@property
	bool initialized() shared {
		return (bits & InitializedBit) != 0;
	}

	@property
	bool containsPointers() shared {
		return (bits & 0x01) != 0;
	}

	@property
	uint index() shared {
		return bits & ArenaMask;
	}

	static getArenaAddress(uint index) {
		assert((index & ~ArenaMask) == 0, "Invalid index!");

		// FIXME: align on cache lines.
		enum ArenaSize = alignUp(Arena.sizeof, CacheLine);
		static shared ulong[ArenaSize / ulong.sizeof][ArenaCount] arenaStore;

		return cast(shared(Arena)*) arenaStore[index].ptr;
	}

public:
	static getInitialized(uint index) {
		auto a = getArenaAddress(index);

		assert(a.initialized, "Arena was not initialized!");
		assert(a.index == index, "Invalid index!");
		assert(a.containsPointers == (index & 0x01), "Invalid pointer status!");

		return a;
	}

	static getOrInitialize(uint index) {
		// Compute the internal index.
		index &= ArenaMask;

		auto a = getArenaAddress(index);
		if (likely(a.initialized)) {
			return a;
		}

		static shared Mutex initMutex;
		initMutex.lock();
		scope(exit) initMutex.unlock();

		// In case it was initialized while we were waiting on the lock.
		if (a.initialized) {
			return a;
		}

		import d.gc.region;
		a.regionAllocator =
			(index & 0x01) ? gPointerRegionAllocator : gDataRegionAllocator;

		// Mark as initialized and return.
		a.bits = index | InitializedBit;

		// Some sanity checks.
		assert(a.initialized, "Arena was not initialized!");
		assert(a.index == index, "Invalid index!");
		assert(a.containsPointers == (index & 0x01), "Invalid pointer status!");

		return a;
	}

public:
	/**
	 * Small allocation facilities.
	 */
	void* allocSmall(ref CachedExtentMap emap, size_t size) shared {
		// TODO: in contracts
		assert(isSmallSize(size));

		auto sizeClass = getSizeClass(size);
		return bins[sizeClass].alloc(&this, emap, sizeClass);
	}

	/**
	 * Large allocation facilities.
	 */
	void* allocLarge(ref CachedExtentMap emap, size_t size,
	                 bool zero = false) shared {
		// TODO: in contracts
		assert(isAllocatableSize(size));

		auto pages = getPageCount(size);
		auto e = allocPages(pages);
		if (unlikely(e is null)) {
			return null;
		}

		if (likely(emap.remap(e))) {
			return e.address;
		}

		// We failed to map the extent, unwind!
		freePages(e);
		return null;
	}

	bool resizeLarge(ref CachedExtentMap emap, Extent* e, size_t size) shared {
		assert(e !is null, "Extent is null!");
		assert(e.isLarge(), "Expected a large extent!");
		assert(e.arenaIndex == index, "Invalid arena index!");

		// The resize must fit in a block.
		if (MaxSmallSize >= size || size > BlockSize || e.size >= BlockSize) {
			return false;
		}

		uint pages = getPageCount(size);
		uint currentPageCount = e.npages;

		if (pages == currentPageCount) {
			return true;
		}

		if (pages > currentPageCount) {
			return growLarge(emap, e, pages);
		}

		shrinkLarge(emap, e, pages);
		return true;
	}

	void shrinkLarge(ref CachedExtentMap emap, Extent* e, uint pages) shared {
		assert(e.isLarge(), "Expected a large extent!");
		assert(!e.isHuge(), "Does not support huge!");
		assert(pages > 0 && pages < e.npages, "Invalid page count!");

		uint delta = e.npages - pages;
		uint index = e.blockIndex + pages;

		emap.clear(e.address + pages * PageSize, delta);

		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Arena*) &this).shrinkAllocImpl(e, index, pages, delta);
	}

	bool growLarge(ref CachedExtentMap emap, Extent* e, uint pages) shared {
		assert(e.isLarge(), "Expected a large extent!");
		assert(!e.isHuge(), "Does not support huge!");
		assert(pages > e.npages, "Invalid page count!");

		auto n = e.blockIndex;
		if (n + pages > PagesInBlock) {
			return false;
		}

		uint currentPages = e.npages;
		uint index = n + currentPages;
		uint delta = pages - currentPages;

		if (!growAlloc(e, index, pages, delta)) {
			return false;
		}

		auto pd = PageDescriptor(e, ExtentClass.large());
		auto endPtr = e.address + currentPages * PageSize;
		if (likely(emap.map(endPtr, delta, pd.next(currentPages)))) {
			return true;
		}

		// We failed to map the new pages, unwind!
		shrinkLarge(emap, e, currentPages);
		return false;
	}

	/**
	 * Deallocation facility.
	 */
	void free(ref CachedExtentMap emap, PageDescriptor pd, void* ptr) shared {
		assert(pd.extent !is null, "Extent is null!");
		assert(pd.extent.contains(ptr), "Invalid ptr!");
		assert(pd.extent.arenaIndex == index, "Invalid arena index!");

		if (unlikely(!pd.isSlab()) || bins[pd.sizeClass].free(&this, ptr, pd)) {
			emap.clear(pd.extent);
			freePages(pd.extent);
		}
	}

package:
	Extent* allocSlab(ref CachedExtentMap emap, ubyte sizeClass) shared {
		import d.gc.slab;
		auto neededPages = binInfos[sizeClass].npages;

		auto ec = ExtentClass.slab(sizeClass);
		auto e = allocPages(neededPages, ec);
		if (unlikely(e is null)) {
			return null;
		}

		if (likely(emap.remap(e, ec))) {
			return e;
		}

		// We failed to map the extent, unwind!
		freePages(e);
		return null;
	}

	void freeSlab(ref CachedExtentMap emap, Extent* e) shared {
		assert(e.isSlab(), "Expected a slab!");

		emap.clear(e);
		freePages(e);
	}

private:
	Extent* allocPages(uint pages, ExtentClass ec) shared {
		assert(pages > 0 && pages <= MaxPagesInLargeAlloc,
		       "Invalid page count!");
		auto mask = ulong.max << getAllocClass(pages);

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Arena*) &this).allocPagesImpl(pages, mask, ec);
	}

	Extent* allocPages(uint pages) shared {
		if (unlikely(pages > MaxPagesInLargeAlloc)) {
			return allocHuge(pages);
		}

		return allocPages(pages, ExtentClass.large());
	}

	Extent* allocHuge(uint pages) shared {
		assert(pages > MaxPagesInLargeAlloc, "Invalid page count!");

		uint extraBlocks = (pages - 1) / PagesInBlock;
		pages = modUp(pages, PagesInBlock);

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Arena*) &this).allocHugeImpl(pages, extraBlocks);
	}

	void freePages(Extent* e) shared {
		assert(isAligned(e.address, PageSize), "Invalid extent address!");

		uint n = e.blockIndex;
		uint pages = modUp(e.npages, PagesInBlock);

		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Arena*) &this).freePagesImpl(e, n, pages);
	}

	bool growAlloc(Extent* e, uint index, uint pages, uint delta) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Arena*) &this).growAllocImpl(e, index, pages, delta);
	}

private:
	Extent* allocPagesImpl(uint pages, ulong mask, ExtentClass ec) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto e = getOrAllocateExtent();
		if (unlikely(e is null)) {
			return null;
		}

		auto block = extractBlock(pages, mask);
		if (unlikely(block is null)) {
			unusedExtents.insert(e);
			return null;
		}

		auto n = block.reserve(pages);
		registerBlock(block);

		auto ptr = block.address + n * PageSize;
		return e.at(ptr, pages, block, ec);
	}

	Extent* allocHugeImpl(uint pages, uint extraBlocks) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(pages <= PagesInBlock, "Invalid page count!");

		auto e = getOrAllocateExtent();
		if (unlikely(e is null)) {
			return null;
		}

		auto block = allocateBlock(extraBlocks);
		if (unlikely(block is null)) {
			unusedExtents.insert(e);
			return null;
		}

		auto n = block.reserve(pages);
		registerBlock(block);

		assert(n == 0, "Unexpected page allocated!");

		auto leadSize = extraBlocks * BlockSize;
		auto ptr = block.address - leadSize;
		auto npages = pages + extraBlocks * PagesInBlock;

		return e.at(ptr, npages, block);
	}

	auto getOrAllocateExtent() {
		assert(mutex.isHeld(), "Mutex not held!");

		auto e = unusedExtents.pop();
		if (e !is null) {
			return e;
		}

		auto slot = base.allocSlot();
		if (slot.address is null) {
			return null;
		}

		return Extent.fromSlot(bits & ArenaMask, slot);
	}

	void freePagesImpl(Extent* e, uint n, uint pages) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(pages > 0 && pages <= PagesInBlock, "Invalid number of pages!");
		assert(n <= PagesInBlock - pages, "Invalid index!");

		auto block = e.block;
		unregisterBlock(block);

		block.release(n, pages);
		if (block.empty) {
			releaseBlock(e, block);
		} else {
			// If the extent is huge, we need to release the concerned region.
			if (e.isHuge()) {
				uint count = (e.size / BlockSize) & uint.max;
				regionAllocator.release(e.address, count);
			}

			registerBlock(block);
		}

		unusedExtents.insert(e);
	}

	void shrinkAllocImpl(Extent* e, uint index, uint pages, uint delta) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(index > 0 && index <= PagesInBlock - pages, "Invalid index!");
		assert(pages > 0 && pages <= PagesInBlock - index,
		       "Invalid number of pages!");
		assert(delta > 0, "Invalid delta!");

		auto block = e.block;
		unregisterBlock(block);

		e.at(e.address, pages, block);
		block.clear(index, delta);

		assert(!block.empty);
		registerBlock(block);
	}

	bool growAllocImpl(Extent* e, uint index, uint pages, uint delta) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(index > 0 && index <= PagesInBlock - delta, "Invalid index!");
		assert(pages > 0 && pages <= PagesInBlock, "Invalid number of pages!");
		assert(delta > 0, "Invalid delta!");

		auto block = e.block;
		unregisterBlock(block);

		auto didGrow = block.growAt(index, delta);
		if (didGrow) {
			e.at(e.address, pages, block);
		}

		registerBlock(block);
		return didGrow;
	}

	/**
	 * BlockDescriptor heaps management.
	 */
	BlockDescriptor* extractBlock(uint pages, ulong mask) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto acfilter = filter & mask;
		if (acfilter == 0) {
			return allocateBlock();
		}

		auto index = countTrailingZeros(acfilter);
		auto block = heaps[index].pop();
		filter &= ~(ulong(heaps[index].empty) << index);

		assert(block !is null);
		return block;
	}

	BlockDescriptor* allocateBlock(uint extraBlocks = 0) {
		assert(mutex.isHeld(), "Mutex not held!");

		if (unusedBlockDescriptors.empty) {
			auto page = base.allocMetadataPage();
			if (page.address is null) {
				return null;
			}

			unusedBlockDescriptors = BlockDescriptor.fromPage(page);
		}

		auto block = unusedBlockDescriptors.pop();
		assert(block !is null);

		if (regionAllocator.acquire(block, extraBlocks)) {
			allBlocks.insert(block);
			return block;
		}

		unusedBlockDescriptors.insert(block);
		return null;
	}

	void unregisterBlock(BlockDescriptor* block) {
		assert(mutex.isHeld(), "Mutex not held!");

		if (block.full) {
			fullBlocks.remove(block);
			return;
		}

		auto index = block.freeRangeClass;
		heaps[index].remove(block);
		filter &= ~(ulong(heaps[index].empty) << index);
	}

	void registerBlock(BlockDescriptor* block) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(!block.empty, "Block is empty!");

		if (block.full) {
			fullBlocks.insert(block);
			return;
		}

		auto index = block.freeRangeClass;
		heaps[index].insert(block);
		filter |= ulong(1) << index;
	}

	void releaseBlock(Extent* e, BlockDescriptor* block) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(block.empty, "Block is not empty!");
		assert(e.block is block, "Invalid Block!");

		// We do not manage this block anymore.
		allBlocks.remove(block);

		auto pages = getBlockCount(e.size);
		auto ptr = alignDown(e.address, BlockSize);
		regionAllocator.release(ptr, pages);

		unusedBlockDescriptors.insert(block);
	}
}

unittest allocLarge {
	import d.gc.arena;
	shared Arena arena;

	auto base = &arena.base;
	scope(exit) arena.base.clear();

	import d.gc.emap;
	static shared ExtentMap emapStorage;
	auto emap = CachedExtentMap(&emapStorage, base);

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	arena.regionAllocator = &regionAllocator;

	auto ptr0 = arena.allocLarge(emap, 4 * PageSize);
	assert(ptr0 !is null);
	auto pd0 = emap.lookup(ptr0);
	assert(pd0.extent.address is ptr0);
	assert(pd0.extent.npages == 4);

	auto ptr1 = arena.allocLarge(emap, 12 * PageSize);
	assert(ptr1 !is null);
	assert(ptr1 is ptr0 + 4 * PageSize);
	auto pd1 = emap.lookup(ptr1);
	assert(pd1.extent.address is ptr1);
	assert(pd1.extent.npages == 12);

	arena.free(emap, pd0, ptr0);
	auto pdf = emap.lookup(ptr0);
	assert(pdf.extent is null);

	// Do not reuse the free slot is there is no room.
	auto ptr2 = arena.allocLarge(emap, 5 * PageSize);
	assert(ptr2 !is null);
	assert(ptr2 is ptr1 + 12 * PageSize);
	auto pd2 = emap.lookup(ptr2);
	assert(pd2.extent.address is ptr2);
	assert(pd2.extent.npages == 5);

	// But do reuse that free slot if there isn't.
	auto ptr3 = arena.allocLarge(emap, 4 * PageSize);
	assert(ptr3 !is null);
	assert(ptr3 is ptr0);
	auto pd3 = emap.lookup(ptr3);
	assert(pd3.extent.address is ptr3);
	assert(pd3.extent.npages == 4);

	// Free everything.
	arena.free(emap, pd1, ptr1);
	arena.free(emap, pd2, ptr2);
	arena.free(emap, pd3, ptr3);
}

unittest allocPages {
	import d.gc.arena;
	shared Arena arena;

	auto base = &arena.base;
	scope(exit) arena.base.clear();

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	arena.regionAllocator = &regionAllocator;

	auto e0 = arena.allocPages(1);
	assert(e0 !is null);
	assert(e0.size == PageSize);

	auto e1 = arena.allocPages(2);
	assert(e1 !is null);
	assert(e1.npages == 2);
	assert(e1.address is e0.address + e0.size);

	auto e0Addr = e0.address;
	arena.freePages(e0);

	// Do not reuse the free slot is there is no room.
	auto e2 = arena.allocPages(3);
	assert(e2 !is null);
	assert(e2.npages == 3);
	assert(e2.address is e1.address + e1.size);

	// But do reuse that free slot if there isn't.
	auto e3 = arena.allocPages(1);
	assert(e3 !is null);
	assert(e3.size == PageSize);
	assert(e3.address is e0Addr);

	// Free everything.
	arena.freePages(e1);
	arena.freePages(e2);
	arena.freePages(e3);

	// Check a wide range of sizes.
	foreach (pages; 1 .. 2 * PagesInBlock) {
		auto e = arena.allocPages(pages);
		assert(e !is null);
		assert(e.npages == pages);
		arena.freePages(e);
	}
}

unittest allocHuge {
	import d.gc.arena;
	shared Arena arena;

	auto base = &arena.base;
	scope(exit) arena.base.clear();

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	arena.regionAllocator = &regionAllocator;
	enum uint AllocSize = PagesInBlock + 1;

	// Allocate a huge extent.
	auto e0 = arena.allocPages(AllocSize);
	assert(e0 !is null);
	assert(e0.npages == AllocSize);

	// Free the huge extent.
	auto e0Addr = e0.address;
	arena.freePages(e0);

	// Reallocating the same run will yield the same memory back.
	e0 = arena.allocPages(AllocSize);
	assert(e0 !is null);
	assert(e0.address is e0Addr);
	assert(e0.npages == AllocSize);

	// Allocate one page on the borrowed block.
	auto e1 = arena.allocPages(1);
	assert(e1 !is null);
	assert(e1.size == PageSize);
	assert(e1.address is e0.address + e0.size);

	// Now, freeing the huge extent will leave a page behind.
	arena.freePages(e0);

	// Allocating another huge extent will use a new range.
	auto e2 = arena.allocPages(AllocSize);
	assert(e2 !is null);
	assert(e2.address is alignUp(e1.address, BlockSize));
	assert(e2.npages == AllocSize);

	// Allocating new small extents fill the borrowed page.
	auto e3 = arena.allocPages(1);
	assert(e3 !is null);
	assert(e3.address is alignDown(e1.address, BlockSize));
	assert(e3.size == PageSize);

	// But allocating just the right size will reuse the region.
	auto e4 = arena.allocPages(PagesInBlock);
	assert(e4 !is null);
	assert(e4.address is e0Addr);
	assert(e4.npages == PagesInBlock);

	// Free everything.
	arena.freePages(e1);
	arena.freePages(e2);
	arena.freePages(e3);
	arena.freePages(e4);
}

unittest resizeLargeShrink {
	import d.gc.arena;
	shared Arena arena;

	auto base = &arena.base;
	scope(exit) arena.base.clear();

	import d.gc.emap;
	static shared ExtentMap emapStorage;
	auto emap = CachedExtentMap(&emapStorage, base);

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	arena.regionAllocator = &regionAllocator;

	// Allocation 0: 35 pages:
	auto ptr0 = arena.allocLarge(emap, 35 * PageSize);
	assert(ptr0 !is null);
	auto pd0 = emap.lookup(ptr0);
	assert(pd0.extent.address is ptr0);
	assert(pd0.extent.npages == 35);
	auto pd0x = emap.lookup(ptr0);
	assert(pd0x.extent.address is ptr0);

	// Allocation 1: 20 pages:
	auto ptr1 = arena.allocLarge(emap, 20 * PageSize);
	assert(ptr1 !is null);
	assert(ptr1 is ptr0 + 35 * PageSize);
	auto pd1 = emap.lookup(ptr1);
	assert(pd1.extent.address is ptr1);
	assert(pd1.extent.npages == 20);

	// Growing by zero is allowed:
	assert(arena.resizeLarge(emap, pd0.extent, 35 * PageSize));

	// Shrink no. 0 down to 10 pages:
	assert(arena.resizeLarge(emap, pd0.extent, 10 * PageSize));
	assert(pd0.extent.address is ptr0);
	assert(pd0.extent.npages == 10);
	auto pd0xx = emap.lookup(ptr0);
	assert(pd0xx.extent.address is ptr0);

	// See that newly-last page is mapped:
	auto okpd = emap.lookup(ptr0 + 9 * PageSize);
	assert(okpd.extent !is null);

	// But the page after the newly-last one, should not be mapped:
	auto badpd = emap.lookup(ptr0 + 10 * PageSize);
	assert(badpd.extent is null);

	// Allocate 25 pages + 1 byte, will not fit in the hole after no.0:
	auto ptr2 = arena.allocLarge(emap, 1 + 25 * PageSize);
	assert(ptr2 !is null);
	auto pd2 = emap.lookup(ptr2);
	assert(pd2.extent.address is ptr2);
	assert(ptr2 is ptr1 + 20 * PageSize);

	// Now allocate precisely 25 pages.
	// This new alloc WILL fit in and fill the free space after no. 0:
	auto ptr3 = arena.allocLarge(emap, 25 * PageSize);
	assert(ptr3 !is null);
	auto pd3 = emap.lookup(ptr3);
	assert(pd3.extent.address is ptr3);
	assert(ptr3 is ptr0 + 10 * PageSize);

	arena.free(emap, pd0, ptr0);
	arena.free(emap, pd1, ptr1);
	arena.free(emap, pd2, ptr2);
	arena.free(emap, pd3, ptr3);

	// Allocate 128 pages:
	auto ptr4 = arena.allocLarge(emap, 128 * PageSize);
	assert(ptr4 !is null);
	auto pd4 = emap.lookup(ptr4);
	assert(pd4.extent.address is ptr4);

	// Allocate 256 pages:
	auto ptr5 = arena.allocLarge(emap, 256 * PageSize);
	assert(ptr5 !is null);
	auto pd5 = emap.lookup(ptr5);
	assert(pd5.extent.address is ptr5);
	assert(pd5.extent.block == pd4.extent.block);

	// Allocate 128 pages, block full:
	auto ptr6 = arena.allocLarge(emap, 128 * PageSize);
	assert(ptr6 !is null);
	auto pd6 = emap.lookup(ptr6);
	assert(pd6.extent.address is ptr6);
	assert(pd6.extent.block == pd5.extent.block);
	assert(pd6.extent.block.full);

	// Shrink first alloc:
	assert(arena.resizeLarge(emap, pd4.extent, 96 * PageSize));
	assert(pd4.extent.npages == 96);
	assert(!pd6.extent.block.full);

	// Shrink second alloc:
	assert(arena.resizeLarge(emap, pd5.extent, 128 * PageSize));
	assert(pd5.extent.npages == 128);

	// Shrink third alloc:
	assert(arena.resizeLarge(emap, pd6.extent, 64 * PageSize));
	assert(pd6.extent.npages == 64);

	// Allocate 128 pages, should go after second alloc:
	auto ptr7 = arena.allocLarge(emap, 128 * PageSize);
	assert(ptr7 !is null);
	auto pd7 = emap.lookup(ptr7);
	assert(pd7.extent.address is ptr7);
	assert(pd7.extent.block == pd6.extent.block);
	assert(ptr7 is ptr5 + 128 * PageSize);

	// Allocate 32 pages, should go after first alloc:
	auto ptr8 = arena.allocLarge(emap, 32 * PageSize);
	assert(ptr8 !is null);
	auto pd8 = emap.lookup(ptr8);
	assert(pd8.extent.address is ptr8);
	assert(pd8.extent.block == pd7.extent.block);
	assert(ptr8 is ptr4 + 96 * PageSize);

	// Allocate 64 pages, should go after third alloc:
	auto ptr9 = arena.allocLarge(emap, 64 * PageSize);
	assert(ptr9 !is null);
	auto pd9 = emap.lookup(ptr9);
	assert(pd9.extent.address is ptr9);
	assert(pd9.extent.block == pd8.extent.block);
	assert(ptr9 is ptr6 + 64 * PageSize);

	// Now full again:
	assert(pd9.extent.block.full);
}

unittest resizeLargeGrow {
	import d.gc.arena;
	shared Arena arena;

	auto base = &arena.base;
	scope(exit) arena.base.clear();

	import d.gc.emap;
	static shared ExtentMap emapStorage;
	auto emap = CachedExtentMap(&emapStorage, base);

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	arena.regionAllocator = &regionAllocator;

	Extent* makeAllocLarge(uint pages) {
		auto ptr = arena.allocLarge(emap, pages * PageSize);
		assert(ptr !is null);
		auto pd = emap.lookup(ptr);
		auto e = pd.extent;
		assert(e !is null);
		assert(e.address is ptr);
		assert(e.npages == pages);
		return e;
	}

	void checkGrowLarge(Extent* e, uint pages) {
		assert(arena.resizeLarge(emap, e, pages * PageSize));
		assert(e.npages == pages);

		// Confirm that the page after the end of the extent is not included in the map:
		auto pdAfter = emap.lookup(e.address + e.size);
		assert(pdAfter.extent !is e);

		auto pd = emap.lookup(e.address);
		// Confirm that the extent correctly grew and remapped:
		for (auto p = e.address; p < e.address + e.size; p += PageSize) {
			auto probe = emap.lookup(p);
			assert(probe.extent == e);
			assert(probe.data == pd.data);
			pd = pd.next();
		}
	}

	// Make three allocations:
	auto e0 = makeAllocLarge(35);
	auto e1 = makeAllocLarge(64);
	assert(e1.address == e0.address + e0.size);
	auto e2 = makeAllocLarge(128);
	assert(e2.address == e1.address + e1.size);

	// Grow by 0 is always permitted:
	assert(arena.resizeLarge(emap, e0, 35 * PageSize));

	// Prohibited grow (not enough space) :
	assert(!arena.resizeLarge(emap, e0, 36 * PageSize));
	assert(!arena.resizeLarge(emap, e2, 414 * PageSize));

	// Grow:
	checkGrowLarge(e2, 413);

	auto pd1 = emap.lookup(e1.address);
	arena.free(emap, pd1, e1.address);

	checkGrowLarge(e0, 44);

	// Prohibited grow (not enough space) :
	assert(!arena.resizeLarge(emap, e0, uint.max * PageSize));
	assert(!arena.resizeLarge(emap, e0, 9999 * PageSize));
	assert(!arena.resizeLarge(emap, e0, 100 * PageSize));

	// Grow:
	checkGrowLarge(e0, 99);
	assert(e0.block.full);

	auto pd2 = emap.lookup(e2.address);
	arena.free(emap, pd2, e2.address);
	assert(!e0.block.full);

	checkGrowLarge(e0, 512);
	assert(e0.block.full);

	auto pd0 = emap.lookup(e0.address);
	arena.free(emap, pd0, e0.address);
}
