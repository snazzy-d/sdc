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

alias FilterType = uint;

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

	enum HeapCount = getAllocClass(PagesInBlock - 1);
	static assert(HeapCount <= 32, "Too many heaps to fit in the filter!");

	FilterType filter;
	PriorityBlockHeap[HeapCount] heaps;

	import d.gc.ring;
	Ring!BlockDescriptor fullBlocks;

	UnusedExtentHeap unusedExtents;
	UnusedBlockHeap unusedBlockDescriptors;
	AllBlockRing allBlocks;

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
		auto e = allocRun(neededPages, neededPages - 1, ec);
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
	                 bool zero = false) shared {
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
	Extent* allocPages(uint pages) shared {
		if (unlikely(pages > MaxPagesInLargeAlloc)) {
			return allocHuge(pages);
		}

		auto allocClass = getAllocClass(pages);
		return allocRun(pages, allocClass, ExtentClass.large());
	}

	Extent* allocRun(uint pages, uint allocClass, ExtentClass ec) shared {
		assert(pages > 0 && pages <= MaxPagesInLargeAlloc,
		       "Invalid page count!");
		assert(allocClass == getAllocClass(pages), "Invalid allocClass!");

		auto mask = FilterType.max << allocClass;

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(PageFiller*) &this).allocRunImpl(pages, mask, ec);
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
	Extent* allocRunImpl(uint pages, FilterType mask, ExtentClass ec) {
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

		auto block = acquireBlock(extraBlocks);
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
	BlockDescriptor* extractBlock(uint pages, FilterType mask) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto acfilter = filter & mask;
		if (acfilter == 0) {
			return acquireBlock();
		}

		auto index = countTrailingZeros(acfilter);
		auto block = heaps[index].pop();
		filter &= ~(FilterType(heaps[index].empty) << index);

		assert(block !is null);
		return block;
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
		filter |= FilterType(1) << index;
	}

	BlockDescriptor* acquireBlock(uint extraBlocks = 0) {
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

	auto e0 = filler.allocPages(1);
	assert(e0 !is null);
	assert(e0.size == PageSize);

	auto e1 = filler.allocPages(2);
	assert(e1 !is null);
	assert(e1.npages == 2);
	assert(e1.address is e0.address + e0.size);

	auto e0Addr = e0.address;
	filler.freePages(e0);

	// Do not reuse the free slot is there is no room.
	auto e2 = arena.filler.allocPages(3);
	assert(e2 !is null);
	assert(e2.npages == 3);
	assert(e2.address is e1.address + e1.size);

	// But do reuse that free slot if there isn't.
	auto e3 = filler.allocPages(1);
	assert(e3 !is null);
	assert(e3.size == PageSize);
	assert(e3.address is e0Addr);

	// Free everything.
	filler.freePages(e1);
	filler.freePages(e2);
	filler.freePages(e3);

	// Check a wide range of sizes.
	foreach (pages; 1 .. 2 * PagesInBlock) {
		auto e = filler.allocPages(pages);
		assert(e !is null);
		assert(e.npages == pages);
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

	enum uint AllocSize = PagesInBlock + 1;

	// Allocate a huge extent.
	auto e0 = filler.allocPages(AllocSize);
	assert(e0 !is null);
	assert(e0.npages == AllocSize);

	// Free the huge extent.
	auto e0Addr = e0.address;
	filler.freePages(e0);

	// Reallocating the same run will yield the same memory back.
	e0 = filler.allocPages(AllocSize);
	assert(e0 !is null);
	assert(e0.address is e0Addr);
	assert(e0.npages == AllocSize);

	// Allocate one page on the borrowed block.
	auto e1 = filler.allocPages(1);
	assert(e1 !is null);
	assert(e1.size == PageSize);
	assert(e1.address is e0.address + e0.size);

	// Now, freeing the huge extent will leave a page behind.
	filler.freePages(e0);

	// Allocating another huge extent will use a new range.
	auto e2 = filler.allocPages(AllocSize);
	assert(e2 !is null);
	assert(e2.address is alignUp(e1.address, BlockSize));
	assert(e2.npages == AllocSize);

	// Allocating new small extents fill the borrowed page.
	auto e3 = filler.allocPages(1);
	assert(e3 !is null);
	assert(e3.address is alignDown(e1.address, BlockSize));
	assert(e3.size == PageSize);

	// But allocating just the right size will reuse the region.
	auto e4 = filler.allocPages(PagesInBlock);
	assert(e4 !is null);
	assert(e4.address is e0Addr);
	assert(e4.npages == PagesInBlock);

	// Free everything.
	filler.freePages(e1);
	filler.freePages(e2);
	filler.freePages(e3);
	filler.freePages(e4);
}
