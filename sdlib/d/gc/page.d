module d.gc.page;

import d.gc.allocclass;
import d.gc.arena;
import d.gc.block;
import d.gc.emap;
import d.gc.extent;
import d.gc.size;
import d.gc.spec;
import d.gc.util;

import sdc.intrinsics;

struct PageFiller {
private:
	@property
	shared(Arena)* arena() shared {
		auto a = cast(Arena*) null;
		auto offset = cast(size_t) &(a.filler);

		auto base = cast(size_t) &this;
		return cast(shared(Arena)*) (base - offset);
	}

	import d.sync.mutex;
	Mutex mutex;

	/**
	 * We separate dense from sparse allocations.
	 * 
	 * Dense allocations are slabs which contains a lot of elements.
	 * In practice, these slabs tends to be long lived, because it
	 * is unlikely that all of their slots get freed at the same time.
	 * In additon, all slabs that require spacial care, such as slabs
	 * that cannot do inline marking, are dense, so segeregating them
	 * allows to iterrate over all of them effisciently.
	 * 
	 * The second set of heaps is used for sparse allocations.
	 * Sparse allocation are slabs with few elements, and large
	 * allocations.
	 */
	enum HeapCount = getAllocClass(PagesInBlock - 1);
	static assert(HeapCount <= 32, "Too many heaps to fit in the filter!");

	uint denseFilter;
	uint sparseFilter;

	PriorityBlockHeap[8] denseHeaps;
	PriorityBlockHeap[HeapCount] sparseHeaps;

	AllBlockRing denseBlocks;
	AllBlockRing sparseBlocks;

	import d.gc.ring;
	Ring!BlockDescriptor fullBlocks;

	UnusedExtentHeap unusedExtents;
	UnusedBlockHeap unusedBlockDescriptors;

	import d.gc.base;
	Base base;

	import d.gc.region;
	shared(RegionAllocator)* regionAllocator;

public:
	/**
	 * Slabs facilities.
	 */
	Extent* allocSlab(ref CachedExtentMap emap, ubyte sizeClass) shared {
		import d.gc.slab;
		auto neededPages = binInfos[sizeClass].npages;

		auto ec = ExtentClass.slab(sizeClass);
		auto e = allocSmallRun(neededPages, neededPages - 1, ec);
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

	/**
	 * Large allocation facilities.
	 */
	void* allocLarge(ref CachedExtentMap emap, uint pages,
	                 bool needZero = false) shared {
		bool dirty;
		auto e = allocPages(pages, dirty);
		if (unlikely(e is null)) {
			return null;
		}

		if (!likely(emap.remap(e))) {
			// We failed to map the extent, unwind!
			freePages(e);
			return null;
		}

		if (needZero && dirty) {
			import d.gc.memmap;
			pages_zero(e.address, e.size);
		}

		return e.address;
	}

	bool resizeLarge(ref CachedExtentMap emap, Extent* e, uint pages) shared {
		assert(e !is null, "Extent is null!");
		assert(e.isLarge(), "Expected a large extent!");
		assert(e.arenaIndex == arena.index, "Invalid arena!");

		// The resize must fit in a block.
		uint currentPageCount = e.npages;
		if (pages > PagesInBlock || currentPageCount >= PagesInBlock) {
			return false;
		}

		if (pages == currentPageCount) {
			return true;
		}

		if (pages > currentPageCount) {
			return growLarge(emap, e, pages);
		}

		shrinkLarge(emap, e, pages);
		return true;
	}

	/**
	 * Allocate and free Pages.
	 */
	Extent* allocPages(uint pages, ref bool dirty) shared {
		if (unlikely(pages > MaxPagesInLargeAlloc)) {
			return allocHuge(pages);
		}

		auto allocClass = getAllocClass(pages);
		return allocRun(pages, allocClass, ExtentClass.large(), dirty);
	}

	Extent* allocSmallRun(uint pages, uint allocClass, ExtentClass ec) shared {
		bool dirty;
		return allocRun(pages, allocClass, ec, dirty);
	}

	Extent* allocRun(uint pages, uint allocClass, ExtentClass ec,
	                 ref bool dirty) shared {
		assert(0 < pages && pages <= MaxPagesInLargeAlloc,
		       "Invalid page count!");
		assert(allocClass == getAllocClass(pages), "Invalid allocClass!");

		auto mask = uint.max << allocClass;

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(PageFiller*) &this).allocRunImpl(pages, mask, ec, dirty);
	}

	Extent* allocHuge(uint pages) shared {
		assert(pages > MaxPagesInLargeAlloc, "Invalid page count!");

		uint extraBlocks = (pages - 1) / PagesInBlock;
		pages = modUp(pages, PagesInBlock);

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(PageFiller*) &this).allocHugeImpl(pages, extraBlocks);
	}

	void freePages(Extent* e) shared {
		assert(isAligned(e.address, PageSize), "Invalid extent address!");
		assert(e.arenaIndex == arena.index, "Invalid arena!");

		uint n = e.blockIndex;
		uint pages = modUp(e.npages, PagesInBlock);

		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(PageFiller*) &this).freePagesImpl(e, n, pages);
	}

private:
	/**
	 * Allocate and free pages, private implementation.
	 */
	Extent* allocRunImpl(uint pages, uint mask, ExtentClass ec,
	                     ref bool dirty) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto e = getOrAllocateExtent();
		if (unlikely(e is null)) {
			return null;
		}

		auto block = extractBlock(pages, mask, ec.dense);
		if (unlikely(block is null)) {
			unusedExtents.insert(e);
			return null;
		}

		auto n = block.reserve(pages, dirty);
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

		auto block = acquireBlock(false, extraBlocks);
		if (unlikely(block is null)) {
			unusedExtents.insert(e);
			return null;
		}

		bool dirty;
		auto n = block.reserve(pages, dirty);

		assert(n == 0, "Unexpected page allocated!");
		assert(!dirty, "Huge allocations shouldn't be dirty!");

		registerBlock(block);

		auto leadSize = extraBlocks * BlockSize;
		auto ptr = block.address - leadSize;
		auto npages = pages + extraBlocks * PagesInBlock;

		return e.at(ptr, npages, block);
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

	/**
	 * Large allocation resizing facilities, private implementation.
	 */
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

	void shrinkLarge(ref CachedExtentMap emap, Extent* e, uint pages) shared {
		assert(e.isLarge(), "Expected a large extent!");
		assert(!e.isHuge(), "Does not support huge!");
		assert(pages > 0 && pages < e.npages, "Invalid page count!");

		uint delta = e.npages - pages;
		uint index = e.blockIndex + pages;

		emap.clear(e.address + pages * PageSize, delta);
		shrinkAlloc(e, index, pages, delta);
	}

	bool growAlloc(Extent* e, uint index, uint pages, uint delta) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(PageFiller*) &this).growAllocImpl(e, index, pages, delta);
	}

	void shrinkAlloc(Extent* e, uint index, uint pages, uint delta) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(PageFiller*) &this).shrinkAllocImpl(e, index, pages, delta);
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

	/**
	 * BlockDescriptor heaps management.
	 */
	auto getFilterPtr(bool dense) {
		return dense ? &denseFilter : &sparseFilter;
	}

	auto getHeaps(bool dense) {
		return dense ? denseHeaps.ptr : sparseHeaps.ptr;
	}

	BlockDescriptor* extractBlock(uint pages, uint mask, bool dense) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto filter = getFilterPtr(dense);
		auto acfilter = *filter & mask;
		if (acfilter == 0) {
			return acquireBlock(dense);
		}

		auto index = countTrailingZeros(acfilter);
		auto heaps = getHeaps(dense);

		auto block = heaps[index].pop();
		*filter &= ~(uint(heaps[index].empty) << index);

		assert(block !is null);
		assert(block.dense == dense);
		return block;
	}

	static uint cappedIndex(BlockDescriptor* block) {
		auto index = block.freeRangeClass;
		if (block.sparse) {
			return index;
		}

		return min!uint(index, 7);
	}

	void unregisterBlock(BlockDescriptor* block) {
		assert(mutex.isHeld(), "Mutex not held!");

		if (block.full) {
			fullBlocks.remove(block);
			return;
		}

		auto index = cappedIndex(block);
		auto filter = getFilterPtr(block.dense);
		auto heaps = getHeaps(block.dense);

		heaps[index].remove(block);
		*filter &= ~(ulong(heaps[index].empty) << index);
	}

	void registerBlock(BlockDescriptor* block) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(!block.empty, "Block is empty!");

		if (block.full) {
			fullBlocks.insert(block);
			return;
		}

		auto index = cappedIndex(block);
		auto filter = getFilterPtr(block.dense);
		auto heaps = getHeaps(block.dense);

		heaps[index].insert(block);
		*filter |= 1 << index;
	}

	auto getAllBlocks(bool dense) {
		return dense ? &denseBlocks : &sparseBlocks;
	}

	BlockDescriptor* acquireBlock(bool dense, uint extraBlocks = 0) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(!dense || extraBlocks == 0, "Huge allocations cannot be dense!");

		if (unusedBlockDescriptors.empty) {
			auto page = base.allocMetadataPage();
			if (page.address is null) {
				return null;
			}

			unusedBlockDescriptors = BlockDescriptor.fromPage(page);
		}

		void* address;
		if (!regionAllocator.acquire(&address, extraBlocks)) {
			return null;
		}

		auto block = unusedBlockDescriptors.pop();
		assert(block !is null);

		block.at(address, dense);
		getAllBlocks(dense).insert(block);
		return block;
	}

	void releaseBlock(Extent* e, BlockDescriptor* block) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(block.empty, "Block is not empty!");
		assert(e.block is block, "Invalid Block!");

		// We do not manage this block anymore.
		getAllBlocks(block.dense).remove(block);

		auto pages = getBlockCount(e.size);
		auto ptr = alignDown(e.address, BlockSize);
		regionAllocator.release(ptr, pages);

		unusedBlockDescriptors.insert(block);
	}

	/**
	 * Extent and BlockDescriptior allocation.
	 */
	auto getOrAllocateExtent() {
		assert(mutex.isHeld(), "Mutex not held!");

		auto e = unusedExtents.pop();
		if (e !is null) {
			return e;
		}

		auto sharedThis = cast(shared(PageFiller)*) &this;

		sharedThis.mutex.unlock();
		scope(success) sharedThis.mutex.lock();

		auto slot = base.allocSlot();
		if (slot.address is null) {
			return null;
		}

		return Extent.fromSlot(sharedThis.arena.index, slot);
	}
}

unittest allocPages {
	import d.gc.arena;
	shared Arena arena;

	auto base = &arena.base;
	scope(exit) arena.base.clear();

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	auto filler = &arena.filler;
	filler.regionAllocator = &regionAllocator;

	auto checkAllocPage(uint pages, bool clean) {
		bool dirty;
		auto e = filler.allocPages(pages, dirty);

		assert(e !is null);
		assert(e.npages == pages);
		assert(dirty == !clean);

		return e;
	}

	auto e0 = checkAllocPage(1, true);
	auto e1 = checkAllocPage(2, true);
	assert(e1.address is e0.address + e0.size);

	auto e0Addr = e0.address;
	filler.freePages(e0);

	// Do not reuse the free slot is there is no room.
	auto e2 = checkAllocPage(3, true);
	assert(e2.address is e1.address + e1.size);

	// But do reuse that free slot if there isn't.
	auto e3 = checkAllocPage(1, false);
	assert(e3.address is e0Addr);

	// Free everything.
	filler.freePages(e1);
	filler.freePages(e2);
	filler.freePages(e3);

	// Check a wide range of sizes.
	foreach (pages; 1 .. 2 * PagesInBlock) {
		auto e = checkAllocPage(pages, true);
		filler.freePages(e);
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

	auto filler = &arena.filler;
	filler.regionAllocator = &regionAllocator;

	auto checkAllocPage(uint pages, bool clean) {
		bool dirty;
		auto e = filler.allocPages(pages, dirty);

		assert(e !is null);
		assert(e.npages == pages);
		assert(dirty == !clean);

		return e;
	}

	enum uint AllocSize = PagesInBlock + 1;

	// Allocate a huge extent.
	auto e0 = checkAllocPage(AllocSize, true);

	// Free the huge extent.
	auto e0Addr = e0.address;
	filler.freePages(e0);

	// Reallocating the same run will yield the same memory back.
	e0 = checkAllocPage(AllocSize, true);
	assert(e0.address is e0Addr);

	// Allocate one page on the borrowed block.
	auto e1 = checkAllocPage(1, true);
	assert(e1.address is e0.address + e0.size);

	// Now, freeing the huge extent will leave a page behind.
	filler.freePages(e0);

	// Allocating another huge extent will use a new range.
	auto e2 = checkAllocPage(AllocSize, true);
	assert(e2.address is alignUp(e1.address, BlockSize));

	// Allocating new small extents fill the borrowed page.
	auto e3 = checkAllocPage(1, false);
	assert(e3.address is alignDown(e1.address, BlockSize));

	// But allocating just the right size will reuse the region.
	auto e4 = checkAllocPage(PagesInBlock, true);
	assert(e4.address is e0Addr);

	// Free everything.
	filler.freePages(e1);
	filler.freePages(e2);
	filler.freePages(e3);
	filler.freePages(e4);
}
