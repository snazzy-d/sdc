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
	void** batchAllocSmall(
		ref CachedExtentMap emap,
		ubyte sizeClass,
		void** top,
		void** bottom,
		size_t slotSize,
	) shared {
		// TODO: in contracts
		assert(isSmallSizeClass(sizeClass));

		import d.gc.slab;
		assert(slotSize == binInfos[sizeClass].slotSize, "Invalid slot size!");

		return bins[sizeClass]
			.batchAllocate(&filler, emap, sizeClass, top, bottom, slotSize);
	}

	uint batchFree(ref CachedExtentMap emap, const(void*)[] worklist,
	               PageDescriptor* pds) shared {
		assert(worklist.length > 0, "Worklist is empty!");
		assert(pds[0].arenaIndex == index, "Erroneous arena index!");

		auto dallocSlabs = cast(Extent**) alloca(worklist.length * PointerSize);

		uint ndalloc = 0;
		scope(success) if (ndalloc > 0) {
			foreach (i; 0 .. ndalloc) {
				// FIXME: batch free to go through the lock once using freeExtentLocked.
				filler.freeExtent(emap, dallocSlabs[i]);
			}
		}

		auto ec = pds[0].extentClass;
		auto sc = ec.sizeClass;
		return bins[sc].batchFree(worklist, pds, dallocSlabs, ndalloc);
	}

	/**
	 * Large allocation facilities.
	 */
	void* allocLarge(ref CachedExtentMap emap, uint pages, bool zero) shared {
		return filler.allocLarge(emap, pages, zero);
	}

	bool growLarge(ref CachedExtentMap emap, Extent* e, uint pages) shared {
		assert(e !is null, "Extent is null!");
		assert(e.isLarge(), "Expected a large extent!");
		assert(e.arenaIndex == index, "Invalid arena index!");
		assert(pages > e.npages, "Invalid page count!");

		return filler.growLarge(emap, e, pages);
	}

	bool shrinkLarge(ref CachedExtentMap emap, Extent* e, uint pages) shared {
		assert(e !is null, "Extent is null!");
		assert(e.isLarge(), "Expected a large extent!");
		assert(e.arenaIndex == index, "Invalid arena index!");
		assert(pages > 0 && pages < e.npages, "Invalid page count!");

		return filler.shrinkLarge(emap, e, pages);
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
	auto filler = &arena.filler;

	size_t expectedUsedPages = 0;

	void checkFreeLarge(Extent* e) {
		auto ptr = e.address;
		auto pages = e.npages;

		arena.freeLarge(emap, e);

		expectedUsedPages -= pages;
		assert(filler.usedPages == expectedUsedPages);

		// Ensure the emap is cleared.
		auto ptrEnd = ptr + pages * PageSize;
		for (auto p = ptr; p < ptrEnd; p += PageSize) {
			auto probe = emap.lookup(p);
			assert(probe.extent is null);
			assert(probe.data == 0);
		}
	}

	auto makeLargeAlloc(uint pages) {
		auto ptr = arena.allocLarge(emap, pages, false);
		assert(ptr !is null);

		expectedUsedPages += pages;
		assert(filler.usedPages == expectedUsedPages);

		auto pd = emap.lookup(ptr);
		auto e = pd.extent;
		assert(e !is null);
		assert(e.address is ptr);
		assert(e.npages == pages);

		for (auto p = ptr; p < e.address + e.size; p += PageSize) {
			auto probe = emap.lookup(p);
			assert(probe.extent is e);
			assert(probe.data == pd.data);
			pd = pd.next();
		}

		return e;
	}

	auto e0 = makeLargeAlloc(4);
	auto e1 = makeLargeAlloc(12);
	assert(e1.address is e0.address + e0.size);

	checkFreeLarge(e0);

	// Do not reuse the free slot is there is no room.
	auto e2 = makeLargeAlloc(5);
	assert(e2.address is e1.address + e1.size);

	// But do reuse that free slot if there isn't.
	auto e3 = makeLargeAlloc(4);
	assert(e1.address is e3.address + e3.size);

	// Free everything.
	checkFreeLarge(e1);
	checkFreeLarge(e2);
	checkFreeLarge(e3);
}

unittest shrinklarge {
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
	auto filler = &arena.filler;

	size_t expectedUsedPages = 0;

	void checkFreeLarge(Extent* e) {
		auto ptr = e.address;
		auto pages = e.npages;

		arena.freeLarge(emap, e);

		expectedUsedPages -= pages;
		assert(filler.usedPages == expectedUsedPages);

		// Ensure the emap is cleared.
		auto ptrEnd = ptr + pages * PageSize;
		for (auto p = ptr; p < ptrEnd; p += PageSize) {
			auto probe = emap.lookup(p);
			assert(probe.extent is null);
			assert(probe.data == 0);
		}
	}

	auto makeLargeAlloc(uint pages) {
		auto ptr = arena.allocLarge(emap, pages, false);
		assert(ptr !is null);

		expectedUsedPages += pages;
		assert(filler.usedPages == expectedUsedPages);

		auto pd = emap.lookup(ptr);
		auto e = pd.extent;
		assert(e !is null);
		assert(e.address is ptr);
		assert(e.npages == pages);

		for (auto p = ptr; p < e.address + e.size; p += PageSize) {
			auto probe = emap.lookup(p);
			assert(probe.extent is e);
			assert(probe.data == pd.data);
			pd = pd.next();
		}

		return e;
	}

	void checkShrinkLarge(Extent* e, uint pages) {
		assert(e.npages >= pages);
		auto delta = e.npages - pages;
		expectedUsedPages -= delta;

		auto ptr = e.address;

		assert(arena.shrinkLarge(emap, e, pages));
		assert(e.address is ptr);
		assert(e.npages == pages);
		assert(filler.usedPages == expectedUsedPages);

		// Confirm that the extent is still mapped.
		auto pd = emap.lookup(e.address);
		for (auto p = e.address; p < e.address + e.size; p += PageSize) {
			auto probe = emap.lookup(p);
			assert(probe.extent is e);
			assert(probe.data == pd.data);
			pd = pd.next();
		}

		// But that page were cleared where it shrunk.
		auto ptrAfter = e.address + e.size;
		auto ptrEnd = ptrAfter + delta * PageSize;

		for (auto p = ptrAfter; p < ptrEnd; p += PageSize) {
			auto probe = emap.lookup(p);
			assert(probe.extent is null);
			assert(probe.data == 0);
		}
	}

	// Round 1.
	auto e0 = makeLargeAlloc(35);
	auto e1 = makeLargeAlloc(20);
	assert(e1.address is e0.address + e0.size);

	// Shrink e0 down to 10 pages.
	checkShrinkLarge(e0, 10);

	// Allocate 26 pages, will not fit in the hole after e0.
	auto e2 = makeLargeAlloc(26);
	assert(e2.address is e1.address + e1.size);

	// Now allocate precisely 25 pages.
	// This new alloc WILL fit in and fill the free space after e0.
	auto e3 = makeLargeAlloc(25);
	assert(e3.address is e0.address + e0.size);

	checkFreeLarge(e0);
	checkFreeLarge(e1);
	checkFreeLarge(e2);
	checkFreeLarge(e3);

	// Round 2.
	auto e4 = makeLargeAlloc(128);
	auto e5 = makeLargeAlloc(256);
	assert(e5.address is e4.address + e4.size);

	auto e6 = makeLargeAlloc(128);
	assert(e6.address is e5.address + e5.size);

	auto block = e4.block;
	assert(block.full);

	// After we shrink something, the block isn't full anymore.
	checkShrinkLarge(e4, 96);
	assert(!block.full);

	checkShrinkLarge(e5, 128);

	// We check for the boundary condition, then shrink to the desired size.
	checkShrinkLarge(e6, 127);
	checkShrinkLarge(e6, 64);

	// Allocate 128 pages, should go after e5.
	auto e7 = makeLargeAlloc(128);
	assert(e7.address is e5.address + e5.size);

	// Allocate 32 pages, should go after e4.
	auto e8 = makeLargeAlloc(32);
	assert(e8.address is e4.address + e4.size);

	// Allocate 64 pages, should go after e6.
	auto e9 = makeLargeAlloc(64);
	assert(e9.address is e6.address + e6.size);

	// Now full again.
	assert(block.full);
}

unittest growLarge {
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
	auto filler = &arena.filler;

	size_t expectedUsedPages = 0;

	void checkFreeLarge(Extent* e) {
		auto ptr = e.address;
		auto pages = e.npages;

		arena.freeLarge(emap, e);

		expectedUsedPages -= pages;
		assert(filler.usedPages == expectedUsedPages);

		// Ensure the emap is cleared.
		auto ptrEnd = ptr + pages * PageSize;
		for (auto p = ptr; p < ptrEnd; p += PageSize) {
			auto probe = emap.lookup(p);
			assert(probe.extent is null);
			assert(probe.data == 0);
		}
	}

	auto makeLargeAlloc(uint pages) {
		auto ptr = arena.allocLarge(emap, pages, false);
		assert(ptr !is null);

		expectedUsedPages += pages;
		assert(filler.usedPages == expectedUsedPages);

		auto pd = emap.lookup(ptr);
		auto e = pd.extent;
		assert(e !is null);
		assert(e.address is ptr);
		assert(e.npages == pages);

		for (auto p = ptr; p < e.address + e.size; p += PageSize) {
			auto probe = emap.lookup(p);
			assert(probe.extent is e);
			assert(probe.data == pd.data);
			pd = pd.next();
		}

		return e;
	}

	void checkGrowLarge(Extent* e, uint pages) {
		assert(pages >= e.npages);
		auto delta = pages - e.npages;
		expectedUsedPages += delta;

		auto ptr = e.address;

		assert(arena.growLarge(emap, e, pages));
		assert(e.address is ptr);
		assert(e.npages == pages);
		assert(filler.usedPages == expectedUsedPages);

		// Check that we did not map past the end.
		auto pdAfter = emap.lookup(e.address + e.size);
		assert(pdAfter.extent !is e);

		// Confirm that the extent correctly grew and remapped.
		auto pd = emap.lookup(e.address);
		for (auto p = e.address; p < e.address + e.size; p += PageSize) {
			auto probe = emap.lookup(p);
			assert(probe.extent is e);
			assert(probe.data == pd.data);
			pd = pd.next();
		}
	}

	auto e0 = makeLargeAlloc(35);
	auto e1 = makeLargeAlloc(64);
	assert(e1.address is e0.address + e0.size);
	auto e2 = makeLargeAlloc(128);
	assert(e2.address is e1.address + e1.size);

	// We cannot grow if there isn't enough space.
	assert(!arena.growLarge(emap, e0, 36));
	assert(!arena.growLarge(emap, e2, 414));

	// But we can if there is space left.
	checkGrowLarge(e2, 413);

	checkFreeLarge(e1);
	checkGrowLarge(e0, 44);

	// There are 99 pages left after e0.
	// Anything larger than this will fail.
	assert(!arena.growLarge(emap, e0, uint.max));
	assert(!arena.growLarge(emap, e0, 9999));
	assert(!arena.growLarge(emap, e0, 100));

	// Grow to take over the 99 remaining pages.
	checkGrowLarge(e0, 99);
	assert(e0.block.full);

	checkFreeLarge(e2);
	assert(!e0.block.full);

	checkGrowLarge(e0, 512);
	assert(e0.block.full);

	checkFreeLarge(e0);
}
