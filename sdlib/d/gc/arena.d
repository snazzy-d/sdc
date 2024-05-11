module d.gc.arena;

import d.gc.emap;
import d.gc.extent;
import d.gc.size;
import d.gc.sizeclass;
import d.gc.spec;

import sdc.intrinsics;

struct Arena {
private:
	ulong bits;

	import d.gc.bin;
	Bin[BinCount] bins;

	import d.gc.page;
	PageFiller filler;

	import d.gc.base;
	Base base;

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
		import d.gc.util;
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

	static getIfInitialized(uint index) {
		auto a = getArenaAddress(index);
		return a.initialized ? a : null;
	}

	static getOrInitialize(uint index) {
		// Compute the internal index.
		index &= ArenaMask;

		auto a = getArenaAddress(index);
		if (likely(a.initialized)) {
			return a;
		}

		import d.sync.mutex;
		static shared Mutex initMutex;
		initMutex.lock();
		scope(exit) initMutex.unlock();

		// In case it was initialized while we were waiting on the lock.
		if (a.initialized) {
			return a;
		}

		import d.gc.region;
		a.filler.regionAllocator =
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
	size_t batchAllocSmall(ref CachedExtentMap emap, ubyte sizeClass,
	                       void*[] buffer, size_t slotSize) shared {
		// TODO: in contracts
		assert(isSmallSizeClass(sizeClass));

		import d.gc.slab;
		assert(slotSize == binInfos[sizeClass].slotSize, "Invalid slot size!");

		return bins[sizeClass]
			.batchAllocate(&filler, emap, sizeClass, buffer, slotSize);
	}

	uint batchFree(ref CachedExtentMap emap, const(void*)[] worklist,
	               PageDescriptor* pds) shared {
		assert(worklist.length > 0, "Worklist is empty!");
		assert(pds[0].arenaIndex == index, "Erroneous arena index!");

		auto dallocSlabs = cast(Extent**) alloca(worklist.length * PointerSize);

		uint dallocCount = 0;
		scope(success) if (dallocCount > 0) {
			foreach (i; 0 .. dallocCount) {
				// FIXME: batch free to go through the lock once.
				filler.freeExtent(emap, dallocSlabs[i]);
			}
		}

		auto ec = pds[0].extentClass;
		return bins[ec.sizeClass]
			.batchFree(worklist, pds, dallocSlabs, dallocCount);
	}

	/**
	 * Large allocation facilities.
	 */
	void* allocLarge(ref CachedExtentMap emap, size_t size, bool zero) shared {
		// TODO: in contracts
		assert(isAllocatableSize(size));

		auto pages = getPageCount(size);
		return filler.allocLarge(emap, pages, zero);
	}

	bool resizeLarge(ref CachedExtentMap emap, Extent* e, size_t size) shared {
		assert(e !is null, "Extent is null!");
		assert(e.isLarge(), "Expected a large extent!");
		assert(e.arenaIndex == index, "Invalid arena index!");

		if (size <= MaxSmallSize) {
			// This would create a small allocation.
			return false;
		}

		uint pages = getPageCount(size);
		return filler.resizeLarge(emap, e, pages);
	}

	void freeLarge(ref CachedExtentMap emap, Extent* e) shared {
		assert(e !is null, "Extent is null!");
		assert(e.isLarge(), "Expected a large extent!");
		assert(e.arenaIndex == index, "Invalid arena index!");

		filler.freeExtent(emap, e);
	}

package:
	/**
	 * GC facilities.
	 */
	void prepareGCCycle(ref CachedExtentMap emap) shared {
		filler.prepareGCCycle(emap);
	}

	void collect(ref CachedExtentMap emap, ubyte gcCycle) shared {
		filler.collect(emap, gcCycle);
	}

	void clearBinsForCollection() shared {
		foreach (i; 0 .. BinCount) {
			bins[i].clearForCollection();
		}
	}

	void combineBinsAfterCollection(
		ref PriorityExtentHeap[BinCount] collectedSlabs
	) shared {
		foreach (i; 0 .. BinCount) {
			bins[i].combineAfterCollection(collectedSlabs[i]);
		}
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

	arena.filler.regionAllocator = &regionAllocator;

	auto makeLargeAlloc(size_t size) {
		return arena.allocLarge(emap, size, false);
	}

	auto ptr0 = makeLargeAlloc(4 * PageSize);
	assert(ptr0 !is null);
	auto pd0 = emap.lookup(ptr0);
	assert(pd0.extent.address is ptr0);
	assert(pd0.extent.npages == 4);

	auto ptr1 = makeLargeAlloc(12 * PageSize);
	assert(ptr1 !is null);
	assert(ptr1 is ptr0 + 4 * PageSize);
	auto pd1 = emap.lookup(ptr1);
	assert(pd1.extent.address is ptr1);
	assert(pd1.extent.npages == 12);

	arena.freeLarge(emap, pd0.extent);
	auto pdf = emap.lookup(ptr0);
	assert(pdf.extent is null);

	// Do not reuse the free slot is there is no room.
	auto ptr2 = makeLargeAlloc(5 * PageSize);
	assert(ptr2 !is null);
	assert(ptr2 is ptr1 + 12 * PageSize);
	auto pd2 = emap.lookup(ptr2);
	assert(pd2.extent.address is ptr2);
	assert(pd2.extent.npages == 5);

	// But do reuse that free slot if there isn't.
	auto ptr3 = makeLargeAlloc(4 * PageSize);
	assert(ptr3 !is null);
	assert(ptr3 is ptr0);
	auto pd3 = emap.lookup(ptr3);
	assert(pd3.extent.address is ptr3);
	assert(pd3.extent.npages == 4);

	// Free everything.
	arena.freeLarge(emap, pd1.extent);
	arena.freeLarge(emap, pd2.extent);
	arena.freeLarge(emap, pd3.extent);
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

	arena.filler.regionAllocator = &regionAllocator;

	auto makeLargeAlloc(size_t size) {
		return arena.allocLarge(emap, size, false);
	}

	// Allocation 0: 35 pages:
	auto ptr0 = makeLargeAlloc(35 * PageSize);
	assert(ptr0 !is null);
	auto pd0 = emap.lookup(ptr0);
	assert(pd0.extent.address is ptr0);
	assert(pd0.extent.npages == 35);
	auto pd0x = emap.lookup(ptr0);
	assert(pd0x.extent.address is ptr0);

	// Allocation 1: 20 pages:
	auto ptr1 = makeLargeAlloc(20 * PageSize);
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
	auto ptr2 = makeLargeAlloc(1 + 25 * PageSize);
	assert(ptr2 !is null);
	auto pd2 = emap.lookup(ptr2);
	assert(pd2.extent.address is ptr2);
	assert(ptr2 is ptr1 + 20 * PageSize);

	// Now allocate precisely 25 pages.
	// This new alloc WILL fit in and fill the free space after no. 0:
	auto ptr3 = makeLargeAlloc(25 * PageSize);
	assert(ptr3 !is null);
	auto pd3 = emap.lookup(ptr3);
	assert(pd3.extent.address is ptr3);
	assert(ptr3 is ptr0 + 10 * PageSize);

	arena.freeLarge(emap, pd0.extent);
	arena.freeLarge(emap, pd1.extent);
	arena.freeLarge(emap, pd2.extent);
	arena.freeLarge(emap, pd3.extent);

	// Allocate 128 pages:
	auto ptr4 = makeLargeAlloc(128 * PageSize);
	assert(ptr4 !is null);
	auto pd4 = emap.lookup(ptr4);
	assert(pd4.extent.address is ptr4);

	// Allocate 256 pages:
	auto ptr5 = makeLargeAlloc(256 * PageSize);
	assert(ptr5 !is null);
	auto pd5 = emap.lookup(ptr5);
	assert(pd5.extent.address is ptr5);
	assert(pd5.extent.block == pd4.extent.block);

	// Allocate 128 pages, block full:
	auto ptr6 = makeLargeAlloc(128 * PageSize);
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
	auto ptr7 = makeLargeAlloc(128 * PageSize);
	assert(ptr7 !is null);
	auto pd7 = emap.lookup(ptr7);
	assert(pd7.extent.address is ptr7);
	assert(pd7.extent.block == pd6.extent.block);
	assert(ptr7 is ptr5 + 128 * PageSize);

	// Allocate 32 pages, should go after first alloc:
	auto ptr8 = makeLargeAlloc(32 * PageSize);
	assert(ptr8 !is null);
	auto pd8 = emap.lookup(ptr8);
	assert(pd8.extent.address is ptr8);
	assert(pd8.extent.block == pd7.extent.block);
	assert(ptr8 is ptr4 + 96 * PageSize);

	// Allocate 64 pages, should go after third alloc:
	auto ptr9 = makeLargeAlloc(64 * PageSize);
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

	arena.filler.regionAllocator = &regionAllocator;

	Extent* makeLargeAlloc(uint pages) {
		auto ptr = arena.allocLarge(emap, pages * PageSize, false);
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
	auto e0 = makeLargeAlloc(35);
	auto e1 = makeLargeAlloc(64);
	assert(e1.address == e0.address + e0.size);
	auto e2 = makeLargeAlloc(128);
	assert(e2.address == e1.address + e1.size);

	// Grow by 0 is always permitted:
	assert(arena.resizeLarge(emap, e0, 35 * PageSize));

	// Prohibited grow (not enough space) :
	assert(!arena.resizeLarge(emap, e0, 36 * PageSize));
	assert(!arena.resizeLarge(emap, e2, 414 * PageSize));

	// Grow:
	checkGrowLarge(e2, 413);

	auto pd1 = emap.lookup(e1.address);
	arena.freeLarge(emap, pd1.extent);

	checkGrowLarge(e0, 44);

	// Prohibited grow (not enough space) :
	assert(!arena.resizeLarge(emap, e0, uint.max * PageSize));
	assert(!arena.resizeLarge(emap, e0, 9999 * PageSize));
	assert(!arena.resizeLarge(emap, e0, 100 * PageSize));

	// Grow:
	checkGrowLarge(e0, 99);
	assert(e0.block.full);

	auto pd2 = emap.lookup(e2.address);
	arena.freeLarge(emap, pd2.extent);
	assert(!e0.block.full);

	checkGrowLarge(e0, 512);
	assert(e0.block.full);

	auto pd0 = emap.lookup(e0.address);
	arena.freeLarge(emap, pd0.extent);
}
