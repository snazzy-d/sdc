module d.gc.arena;

import d.gc.allocclass;
import d.gc.emap;
import d.gc.extent;
import d.gc.hpd;
import d.gc.sizeclass;
import d.gc.spec;
import d.gc.util;

import sdc.intrinsics;

struct Arena {
private:
	ulong bits;

	import d.gc.base;
	Base base;

	import d.gc.region;
	shared(RegionAllocator)* regionAllocator;

	import d.sync.mutex;
	Mutex mutex;

	import d.gc.heap;
	Heap!(Extent, unusedExtentCmp) unusedExtents;
	Heap!(HugePageDescriptor, unusedHPDCmp) unusedHPDs;

	ulong filter;

	enum PageCount = HugePageDescriptor.PageCount;
	enum HeapCount = getAllocClass(PageCount);
	static assert(HeapCount <= 64, "Too many heaps to fit in the filter!");

	Heap!(HugePageDescriptor, epochHPDCmp)[HeapCount] heaps;

	import d.gc.bin;
	Bin[ClassCount.Small] bins;

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
	void* allocSmall(shared(ExtentMap)* emap, size_t size) shared {
		// TODO: in contracts
		assert(size > 0 && size <= SizeClass.Small);

		auto sizeClass = getSizeClass(size);
		assert(sizeClass < ClassCount.Small);

		return bins[sizeClass].alloc(&this, emap, sizeClass);
	}

	/**
	 * Large allocation facilities.
	 */
	void* allocLarge(shared(ExtentMap)* emap, size_t size,
	                 bool zero = false) shared {
		// TODO: in contracts
		assert(size > SizeClass.Small && size <= MaxAllocationSize);

		auto computedPageCount = alignUp(size, PageSize) / PageSize;
		uint pages = computedPageCount & uint.max;

		assert(pages == computedPageCount, "Unexpected page count!");

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

	/**
	 * Deallocation facility.
	 */
	void free(shared(ExtentMap)* emap, PageDescriptor pd, void* ptr) shared {
		assert(pd.extent !is null, "Extent is null!");
		assert(pd.extent.contains(ptr), "Invalid ptr!");
		assert(pd.extent.arenaIndex == index, "Invalid arena index!");

		if (unlikely(!pd.isSlab()) || bins[pd.sizeClass].free(&this, ptr, pd)) {
			emap.clear(pd.extent);
			freePages(pd.extent);
		}
	}

package:
	Extent* allocSlab(shared(ExtentMap)* emap, ubyte sizeClass) shared {
		auto ec = ExtentClass.slab(sizeClass);
		auto e = allocPages(binInfos[sizeClass].needPages, ec);
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

	void freeSlab(shared(ExtentMap)* emap, Extent* e) shared {
		assert(e.isSlab(), "Expected a slab!");

		emap.clear(e);
		freePages(e);
	}

private:
	Extent* allocPages(uint pages, ExtentClass ec) shared {
		assert(pages > 0 && pages <= PageCount, "Invalid page count!");
		auto mask = ulong.max << getAllocClass(pages);

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Arena*) &this).allocPagesImpl(pages, mask, ec);
	}

	Extent* allocPages(uint pages) shared {
		if (unlikely(pages > PageCount)) {
			return allocHuge(pages);
		}

		return allocPages(pages, ExtentClass.large());
	}

	Extent* allocHuge(uint pages) shared {
		assert(pages > PageCount, "Invalid page count!");

		uint extraPages = (pages - 1) / PageCount;
		pages = modUp(pages, PageCount);

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Arena*) &this).allocHugeImpl(pages, extraPages);
	}

	void freePages(Extent* e) shared {
		assert(isAligned(e.address, PageSize), "Invalid extent address!");
		assert(isAligned(e.size, PageSize), "Invalid extent size!");

		uint n = 0;
		if (!e.isHuge()) {
			assert(e.hpd.address is alignDown(e.address, HugePageSize),
			       "Invalid hpd!");

			n = ((cast(size_t) e.address) / PageSize) % PageCount;
		}

		auto computedPageCount = modUp(e.size / PageSize, PageCount);
		uint pages = computedPageCount & uint.max;

		assert(pages == computedPageCount, "Unexpected page count!");

		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Arena*) &this).freePagesImpl(e, n, pages);
	}

private:
	Extent* allocPagesImpl(uint pages, ulong mask, ExtentClass ec) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto e = getOrAllocateExtent();
		if (unlikely(e is null)) {
			return null;
		}

		auto hpd = extractHPD(pages, mask);
		if (unlikely(hpd is null)) {
			unusedExtents.insert(e);
			return null;
		}

		auto n = hpd.reserve(pages);
		if (!hpd.full) {
			registerHPD(hpd);
		}

		auto ptr = hpd.address + n * PageSize;
		auto size = pages * PageSize;

		return e.at(ptr, size, hpd, ec);
	}

	HugePageDescriptor* extractHPD(uint pages, ulong mask) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto acfilter = filter & mask;
		if (acfilter == 0) {
			return allocateHPD();
		}

		auto index = countTrailingZeros(acfilter);
		auto hpd = heaps[index].pop();
		filter &= ~(ulong(heaps[index].empty) << index);

		return hpd;
	}

	Extent* allocHugeImpl(uint pages, uint extraPages) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto e = getOrAllocateExtent();
		if (unlikely(e is null)) {
			return null;
		}

		auto hpd = allocateHPD(extraPages);
		if (unlikely(hpd is null)) {
			unusedExtents.insert(e);
			return null;
		}

		auto n = hpd.reserve(pages);
		assert(n == 0, "Unexpected page allocated!");

		if (!hpd.full) {
			registerHPD(hpd);
		}

		auto leadSize = extraPages * HugePageSize;
		auto ptr = hpd.address - leadSize;
		auto size = leadSize + pages * PageSize;

		return e.at(ptr, size, hpd);
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

	HugePageDescriptor* allocateHPD(uint extraPages = 0) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto hpd = unusedHPDs.pop();
		if (hpd is null) {
			auto slot = base.allocSlot();
			if (slot.address is null) {
				return null;
			}

			hpd = HugePageDescriptor.fromSlot(slot);
		}

		if (regionAllocator.acquire(hpd, extraPages)) {
			return hpd;
		}

		unusedHPDs.insert(hpd);
		return null;
	}

	void freePagesImpl(Extent* e, uint n, uint pages) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(pages > 0 && pages <= PageCount, "Invalid number of pages!");
		assert(n <= PageCount - pages, "Invalid index!");

		auto hpd = e.hpd;
		if (!hpd.full) {
			auto index = getFreeSpaceClass(hpd.longestFreeRange);
			heaps[index].remove(hpd);
			filter &= ~(ulong(heaps[index].empty) << index);
		}

		hpd.release(n, pages);
		if (hpd.empty) {
			releaseHPD(e, hpd);
		} else {
			// If the extent is huge, we need to release the concerned region.
			if (e.isHuge()) {
				uint count = (e.size / HugePageSize) & uint.max;
				regionAllocator.release(e.address, count);
			}

			registerHPD(hpd);
		}

		unusedExtents.insert(e);
	}

	void registerHPD(HugePageDescriptor* hpd) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(!hpd.full, "HPD is full!");
		assert(!hpd.empty, "HPD is empty!");

		auto index = getFreeSpaceClass(hpd.longestFreeRange);
		heaps[index].insert(hpd);
		filter |= ulong(1) << index;
	}

	void releaseHPD(Extent* e, HugePageDescriptor* hpd) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(hpd.empty, "HPD is not empty!");
		assert(e.hpd is hpd, "Invalid HPD!");

		auto ptr = alignDown(e.address, HugePageSize);
		uint pages = (alignUp(e.size, HugePageSize) / HugePageSize) & uint.max;
		regionAllocator.release(ptr, pages);

		unusedHPDs.insert(hpd);
	}
}

unittest allocLarge {
	import d.gc.arena;
	shared Arena arena;

	auto base = &arena.base;
	scope(exit) arena.base.clear();

	import d.gc.emap;
	static shared ExtentMap emap;
	emap.tree.base = base;

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	arena.regionAllocator = &regionAllocator;

	auto ptr0 = arena.allocLarge(&emap, 4 * PageSize);
	assert(ptr0 !is null);
	auto pd0 = emap.lookup(ptr0);
	assert(pd0.extent.address is ptr0);
	assert(pd0.extent.size == 4 * PageSize);

	auto ptr1 = arena.allocLarge(&emap, 12 * PageSize);
	assert(ptr1 !is null);
	assert(ptr1 is ptr0 + 4 * PageSize);
	auto pd1 = emap.lookup(ptr1);
	assert(pd1.extent.address is ptr1);
	assert(pd1.extent.size == 12 * PageSize);

	arena.free(&emap, pd0, ptr0);
	auto pdf = emap.lookup(ptr0);
	assert(pdf.extent is null);

	// Do not reuse the free slot is there is no room.
	auto ptr2 = arena.allocLarge(&emap, 5 * PageSize);
	assert(ptr2 !is null);
	assert(ptr2 is ptr1 + 12 * PageSize);
	auto pd2 = emap.lookup(ptr2);
	assert(pd2.extent.address is ptr2);
	assert(pd2.extent.size == 5 * PageSize);

	// But do reuse that free slot if there isn't.
	auto ptr3 = arena.allocLarge(&emap, 4 * PageSize);
	assert(ptr3 !is null);
	assert(ptr3 is ptr0);
	auto pd3 = emap.lookup(ptr3);
	assert(pd3.extent.address is ptr3);
	assert(pd3.extent.size == 4 * PageSize);

	// Free everything.
	arena.free(&emap, pd1, ptr1);
	arena.free(&emap, pd2, ptr2);
	arena.free(&emap, pd3, ptr3);
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
	assert(e1.size == 2 * PageSize);
	assert(e1.address is e0.address + e0.size);

	auto e0Addr = e0.address;
	arena.freePages(e0);

	// Do not reuse the free slot is there is no room.
	auto e2 = arena.allocPages(3);
	assert(e2 !is null);
	assert(e2.size == 3 * PageSize);
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

	enum uint PageCount = Arena.PageCount;
	enum uint AllocSize = PageCount + 1;

	// Allocate a huge extent.
	auto e0 = arena.allocPages(AllocSize);
	assert(e0 !is null);
	assert(e0.size == AllocSize * PageSize);

	// Free the huge extent.
	auto e0Addr = e0.address;
	arena.freePages(e0);

	// Reallocating the same run will yield the same memory back.
	e0 = arena.allocPages(AllocSize);
	assert(e0 !is null);
	assert(e0.address is e0Addr);
	assert(e0.size == AllocSize * PageSize);

	// Allocate one page on the borrowed huge page.
	auto e1 = arena.allocPages(1);
	assert(e1 !is null);
	assert(e1.size == PageSize);
	assert(e1.address is e0.address + e0.size);

	// Now, freeing the huge extent will leave a page behind.
	arena.freePages(e0);

	// Allocating another huge extent will use a new range.
	auto e2 = arena.allocPages(AllocSize);
	assert(e2 !is null);
	assert(e2.address is alignUp(e1.address, HugePageSize));
	assert(e2.size == AllocSize * PageSize);

	// Allocating new small extents fill the borrowed page.
	auto e3 = arena.allocPages(1);
	assert(e3 !is null);
	assert(e3.address is alignDown(e1.address, HugePageSize));
	assert(e3.size == PageSize);

	// But allocating just the right size will reuse the region.
	auto e4 = arena.allocPages(PageCount);
	assert(e4 !is null);
	assert(e4.address is e0Addr);
	assert(e4.size == PageCount * PageSize);

	// Free everything.
	arena.freePages(e1);
	arena.freePages(e2);
	arena.freePages(e3);
	arena.freePages(e4);
}
