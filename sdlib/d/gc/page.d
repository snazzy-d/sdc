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

extern(C)
void __sd_destroyBlockCtx(void* ptr, size_t usedSpace, void* finalizer);

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
	shared Mutex mutex;

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

	OutlinedBitmap* outlinedBitmaps;

	import d.gc.base;
	shared Base base;

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

	/**
	 * Large allocation facilities.
	 */
	void* allocLarge(ref CachedExtentMap emap, uint pages, bool zero) shared {
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

		if (zero && dirty) {
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

	void freeExtent(ref CachedExtentMap emap, Extent* e) shared {
		emap.clear(e);
		freePages(e);
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

	/**
	 * GC facilities.
	 */
	void prepareGCCycle(ref CachedExtentMap emap) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(PageFiller*) &this).prepareGCCycleImpl(emap);
	}

	void collect(ref CachedExtentMap emap, ubyte gcCycle) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(PageFiller*) &this).collectImpl(emap, gcCycle);
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
			// If the extent is larger than a block,
			// we need to release the extra region.
			if (e.npages > PagesInBlock) {
				mutex.unlock();
				scope(exit) mutex.lock();

				regionAllocator.release(e.address, e.npages / PagesInBlock);
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
		scope(success) registerBlock(block);

		if (!block.growAt(index, delta)) {
			return false;
		}

		e.at(e.address, pages, block);
		return true;
	}

	void shrinkAllocImpl(Extent* e, uint index, uint pages, uint delta) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(index > 0 && index <= PagesInBlock - pages, "Invalid index!");
		assert(pages > 0 && pages <= PagesInBlock - index,
		       "Invalid number of pages!");
		assert(delta > 0, "Invalid delta!");

		auto block = e.block;
		unregisterBlock(block);
		scope(success) registerBlock(block);

		e.at(e.address, pages, block);

		block.clear(index, delta);
		assert(!block.empty);
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
		unusedBlockDescriptors.insert(block);

		mutex.unlock();
		scope(exit) mutex.lock();

		auto nblocks = alignUp(e.npages, PagesInBlock) / PagesInBlock;
		assert(nblocks <= uint.max);

		auto ptr = alignDown(e.address, BlockSize);
		regionAllocator.release(ptr, nblocks & uint.max);
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

		{
			mutex.unlock();
			scope(success) mutex.lock();

			auto slot = base.allocSlot();
			if (slot.address is null) {
				goto Exit;
			}

			auto sharedThis = cast(shared(PageFiller)*) &this;
			e = Extent.fromSlot(sharedThis.arena.index, slot);
		}

		unusedExtents.insert(e);

	Exit:
		return unusedExtents.pop();
	}

	/**
	 * GC facilities.
	 */
	struct OutlinedBitmap {
		OutlinedBitmap* next;
		Extent* extent;

		@property
		ulong[] bitmaps() {
			/**
			 * Bitmaps are storaed on a page. The OutlinedBitmap lives at
			 * the start of the page, and the bitmaps nimbles come next.
			 */
			enum NimbleCount =
				(PageSize - OutlinedBitmap.sizeof) / ulong.sizeof;

			auto ptr = cast(ulong*) (&this + 1);
			return ptr[0 .. NimbleCount];
		}
	}

	ulong[] allocGCBitmap() {
		assert(mutex.isHeld(), "Mutex not held!");

		// Allocate one page.
		bool dirty;
		auto e = allocRunImpl(1, uint.max, ExtentClass.large(), dirty);
		if (unlikely(e is null)) {
			return [];
		}

		if (dirty) {
			import d.gc.memmap;
			pages_zero(e.address, e.size);
		}

		auto ob = cast(OutlinedBitmap*) e.address;
		ob.next = outlinedBitmaps;
		ob.extent = e;

		outlinedBitmaps = ob;
		return ob.bitmaps;
	}

	void prepareGCCycleImpl(ref CachedExtentMap emap) {
		assert(mutex.isHeld(), "Mutex not held!");

		ulong[] bitmaps;

		for (auto r = denseBlocks.range; !r.empty; r.popFront()) {
			auto block = r.front;
			auto bem = emap.blockLookup(block.address);

			uint i = 0;
			while (i < PagesInBlock) {
				i = block.nextAllocatedPage(i);
				if (i >= PagesInBlock) {
					break;
				}

				auto pd = bem.lookup(i);
				auto e = pd.extent;
				assert(e !is null);

				auto ec = pd.extentClass;
				auto sc = ec.sizeClass;

				/**
				 * Because we might not be touching the first half of the Extent,
				 * we make sure we don't take a miss and use binInfos instead.
				 */
				import d.gc.slab;
				i += binInfos[sc].npages;

				import d.gc.sizeclass;
				if (ec.supportsInlineMarking) {
					import d.gc.bitmap;
					auto bmp = cast(Bitmap!128*) &e.slabMetadataMarks;
					bmp.clear();
					continue;
				}

				auto nslots = binInfos[sc].nslots;
				auto nimble = alignUp(nslots, 64) / 64;
				if (bitmaps.length < nimble) {
					bitmaps = allocGCBitmap();
				}

				assert(bitmaps.length >= nimble,
				       "Failed to allocate GC bitmaps.");

				e.outlineMarksBuffer = bitmaps.ptr;
				bitmaps = bitmaps[nimble .. bitmaps.length];
			}
		}
	}

	void collectImpl(ref CachedExtentMap emap, ubyte gcCycle) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto sharedThis = cast(shared(PageFiller)*) &this;
		sharedThis.arena.clearBinsForCollection();

		import d.gc.sizeclass;
		PriorityExtentHeap[BinCount] collectedSlabs;
		auto slabs = collectedSlabs[0 .. BinCount];

		collectDenseAllocations(emap, slabs);
		collectSparseAllocations(emap, slabs, gcCycle);

		sharedThis.arena.combineBinsAfterCollection(collectedSlabs);
	}

	/**
	 * Dense collection.
	 */
	void collectOutlinedBitmaps() {
		assert(mutex.isHeld(), "Mutex not held!");

		auto ob = outlinedBitmaps;
		scope(success) outlinedBitmaps = null;

		while (ob !is null) {
			// We could free and then fetch next, because we are the GC,
			// but I'd rather avoid this kind of tricks.
			auto next = ob.next;
			scope(success) ob = next;

			auto e = ob.extent;
			freePagesImpl(e, e.blockIndex, 1);
		}
	}

	void collectDenseAllocations(ref CachedExtentMap emap,
	                             PriorityExtentHeap[] slabs) {
		assert(mutex.isHeld(), "Mutex not held!");

		PriorityExtentHeap deadExtents;

		for (auto r = denseBlocks.range; !r.empty; r.popFront()) {
			auto block = r.front;
			auto bem = emap.blockLookup(block.address);

			uint i = 0;
			while (i < PagesInBlock) {
				i = block.nextAllocatedPage(i);
				if (i >= PagesInBlock) {
					break;
				}

				auto pd = bem.lookup(i);
				auto e = pd.extent;
				assert(e !is null);
				assert(e.isSlab());

				auto ec = pd.extentClass;
				auto sc = ec.sizeClass;

				assert(ec.dense);

				auto npages = e.npages;
				i += npages;

				import d.gc.slab;
				auto nslots = binInfos[sc].nslots;
				auto ssize = binInfos[sc].slotSize;
				auto nimble = alignUp(nslots, 64) / 64;

				ulong* bmp;
				if (ec.supportsInlineMarking) {
					bmp = cast(ulong*) &e.slabMetadataMarks;
				} else {
					bmp = e.outlineMarksBuffer;
					e.outlineMarksBuffer = null;
				}

				assert(bmp !is null);

				uint count = 0;
				ulong occupancyMask = 0;

				foreach (i; 0 .. nimble) {
					auto oldOccupancy = e.slabData.rawContent[i];
					auto newOccupancy = oldOccupancy & bmp[i];

					if (ec.supportsMetadata) {
						auto toRemove = (oldOccupancy ^ newOccupancy)
							& e.slabMetadataFlags.rawNimbleAtomic(cast(uint) i);
						if (toRemove) {
							// All set bits in toRemove have metadata.
							auto baseidx = i * 64;
							while (toRemove != 0) {
								uint bit = countTrailingZeros(toRemove);
								uint idx = cast(uint) (bit + baseidx);
								// NOTE: this copies techniques/code from
								// SlabAllocInfo, but that code starts with a
								// pointer and gives us info we already have.
								// So we don't want to do that work again.
								auto ptr = e.address + idx * ssize;
								auto fptr =
									cast(size_t*) (ptr + ssize - PointerSize);
								enum FinalizerBit =
									nativeToBigEndian!size_t(0x2);
								if (*fptr & FinalizerBit) {
									// call the finalizer
									auto freeSpace = readPackedFreeSpace(
										(cast(ushort*) fptr) + 3);
									__sd_destroyBlockCtx(
										ptr,
										ssize - freeSpace - PointerSize,
										cast(void*)
											((cast(size_t) *fptr) & AddressMask)
									);
								}

								// clear the bit
								toRemove ^= 1UL << bit;
							}
						}
					}

					occupancyMask |= newOccupancy;
					count += popCount(oldOccupancy ^ newOccupancy);

					e.slabData.rawContent[i] = newOccupancy;
				}

				// The slab is empty.
				if (occupancyMask == 0) {
					deadExtents.insert(e);
					continue;
				}

				e.bits += count * Extent.FreeSlotsUnit;

				if (e.nfree > 0) {
					slabs[ec.sizeClass].insert(e);
				}
			}
		}

		while (!deadExtents.empty) {
			freeExtentLocked(emap, deadExtents.pop());
		}

		collectOutlinedBitmaps();
	}

	/**
	 * Sparse collection.
	 */
	void collectSparseAllocations(ref CachedExtentMap emap,
	                              PriorityExtentHeap[] slabs, ubyte gcCycle) {
		assert(mutex.isHeld(), "Mutex not held!");

		PriorityExtentHeap deadExtents;

		for (auto r = sparseBlocks.range; !r.empty; r.popFront()) {
			auto block = r.front;
			auto bem = emap.blockLookup(block.address);

			uint i = 0;
			while (i < PagesInBlock) {
				i = block.nextAllocatedPage(i);
				if (i >= PagesInBlock) {
					break;
				}

				auto pd = bem.lookup(i);
				auto e = pd.extent;
				assert(e !is null, "GC Metadata leftovers?");

				auto npages = e.npages;
				i += npages;

				auto w = e.gcWord.load();
				auto ec = pd.extentClass;
				if (ec.isLarge()) {
					if (w != gcCycle) {
						// We have not marked this extent this cycle.
						// check for a finalizer
						auto f = e.finalizer;
						if (f !is null) {
							__sd_destroyBlockCtx(
								e.address, e.usedCapacity - PointerSize, f);
						}

						deadExtents.insert(e);
					}

					continue;
				}

				// need to know if anything has metadata
				auto hasMeta = e.slabMetadataFlags.rawNimbleAtomic(0);

				// If the cycle do not match, all the elements are dead. If no
				// metadata exists, then we can safely clear the whole thing.
				if (hasMeta == 0 && ((w & 0xff) != gcCycle)) {
					deadExtents.insert(e);
					continue;
				}

				auto oldOccupancy = e.slabData.rawContent[0];
				auto newOccupancy = oldOccupancy & (w >> 8);

				// need to check dying blocks for finalizers.
				hasMeta &= (oldOccupancy ^ newOccupancy);
				if (hasMeta) {
					import d.gc.slab;
					auto ssize = binInfos[ec.sizeClass].slotSize;
					// All set bits in hasMeta have metadata.
					auto baseidx = i * 64;
					while (hasMeta != 0) {
						uint bit = countTrailingZeros(hasMeta);
						// NOTE: this copies techniques/code from
						// SlabAllocInfo, but that code starts with a
						// pointer and gives us info we already have.
						// So we don't want to do that work again.
						auto ptr = e.address + bit * ssize;
						auto fptr = cast(size_t*) (ptr + ssize - PointerSize);
						enum FinalizerBit = nativeToBigEndian!size_t(0x2);
						if (*fptr & FinalizerBit) {
							// call the finalizer
							auto freeSpace =
								readPackedFreeSpace((cast(ushort*) fptr) + 3);
							__sd_destroyBlockCtx(
								ptr,
								ssize - freeSpace - PointerSize,
								cast(void*) ((cast(size_t) *fptr) & AddressMask)
							);
						}

						// clear the bit
						hasMeta ^= 1UL << bit;
					}
				}

				// The slab is empty.
				if (newOccupancy == 0) {
					deadExtents.insert(e);
					continue;
				}

				auto count = popCount(oldOccupancy ^ newOccupancy);

				e.slabData.rawContent[0] = newOccupancy;
				e.bits += count * Extent.FreeSlotsUnit;

				if (e.nfree > 0) {
					slabs[ec.sizeClass].insert(e);
				}
			}
		}

		while (!deadExtents.empty) {
			freeExtentLocked(emap, deadExtents.pop());
		}
	}

	void freeExtentLocked(ref CachedExtentMap emap, Extent* e) {
		assert(isAligned(e.address, PageSize), "Invalid extent address!");

		emap.clear(e);

		uint n = e.blockIndex;
		uint pages = modUp(e.npages, PagesInBlock);

		(cast(PageFiller*) &this).freePagesImpl(e, n, pages);
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

	auto checkAllocPage(uint pages, bool clean, bool huge) {
		bool dirty;
		auto e = filler.allocPages(pages, dirty);

		assert(e !is null);
		assert(e.npages == pages);
		assert(dirty == !clean);

		assert(e.isHuge() == huge);
		return e;
	}

	enum uint AllocSize = PagesInBlock + 1;

	// Allocate a huge extent.
	auto e0 = checkAllocPage(AllocSize, true, true);

	// Free the huge extent.
	auto e0Addr = e0.address;
	filler.freePages(e0);

	// Reallocating the same run will yield the same memory back.
	e0 = checkAllocPage(AllocSize, true, true);
	assert(e0.address is e0Addr);

	// Allocate one page on the borrowed block.
	auto e1 = checkAllocPage(1, true, false);
	assert(e1.address is e0.address + e0.size);

	// Now, freeing the huge extent will leave a page behind.
	filler.freePages(e0);

	// Allocating another huge extent will use a new range.
	auto e2 = checkAllocPage(AllocSize, true, true);
	assert(e2.address is alignUp(e1.address, BlockSize));

	// Allocating new small extents fill the borrowed page.
	auto e3 = checkAllocPage(1, false, false);
	assert(e3.address is alignDown(e1.address, BlockSize));

	// But allocating just the right size will reuse the region.
	auto e4 = checkAllocPage(PagesInBlock, true, true);
	assert(e4.address is e0Addr);

	// Free everything.
	filler.freePages(e1);
	filler.freePages(e2);
	filler.freePages(e3);
	filler.freePages(e4);

	// Check boundaries.
	auto e5 = checkAllocPage(MaxPagesInLargeAlloc, true, false);
	auto e6 = checkAllocPage(MaxPagesInLargeAlloc + 1, true, true);

	filler.freePages(e5);
	filler.freePages(e6);
}
