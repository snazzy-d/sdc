module d.gc.allocator;

import d.gc.allocclass;
import d.gc.arena;
import d.gc.base;
import d.gc.extent;
import d.gc.heap;
import d.gc.hpd;
import d.gc.spec;
import d.gc.util;

struct Allocator {
private:
	import d.gc.region;
	shared(RegionAllocator)* regionAllocator;

	import d.gc.emap;
	shared(ExtentMap)* emap;

	import d.sync.mutex;
	Mutex mutex;

	Heap!(Extent, unusedExtentCmp) unusedExtents;
	Heap!(HugePageDescriptor, unusedHPDCmp) unusedHPDs;

	ulong filter;

	enum PageCount = HugePageDescriptor.PageCount;
	enum HeapCount = getAllocClass(PageCount);
	static assert(HeapCount <= 64, "Too many heaps to fit in the filter!");

	Heap!(HugePageDescriptor, epochHPDCmp)[HeapCount] heaps;

public:
	Extent* allocPages(shared(Arena)* arena, uint pages, bool is_slab,
	                   ubyte sizeClass) shared {
		assert(pages > 0 && pages <= PageCount, "Invalid page count!");
		auto mask = ulong.max << getAllocClass(pages);

		Extent* e;

		{
			mutex.lock();
			scope(exit) mutex.unlock();

			e = (cast(Allocator*) &this)
				.allocPagesImpl(arena, pages, mask, is_slab, sizeClass);
		}

		if (e !is null) {
			emap.remap(e, is_slab, sizeClass);
		}

		return e;
	}

	Extent* allocPages(shared(Arena)* arena, uint pages,
	                   ubyte sizeClass) shared {
		return allocPages(arena, pages, true, sizeClass);
	}

	Extent* allocPages(shared(Arena)* arena, uint pages) shared {
		if (pages > PageCount) {
			return allocHuge(arena, pages);
		}

		// FIXME: Overload resolution doesn't cast this properly.
		return allocPages(arena, pages, false, ubyte(0));
	}

	Extent* allocHuge(shared(Arena)* arena, uint pages) shared {
		assert(pages > PageCount, "Invalid page count!");

		uint extraPages = (pages - 1) / PageCount;
		pages = modUp(pages, PageCount);

		Extent* e;

		{
			mutex.lock();
			scope(exit) mutex.unlock();

			e = (cast(Allocator*) &this)
				.allocHugeImpl(arena, pages, extraPages);
		}

		if (e !is null) {
			emap.remap(e);
		}

		return e;
	}

	void freePages(Extent* e) shared {
		assert(isAligned(e.addr, PageSize), "Invalid extent addr!");
		assert(isAligned(e.size, PageSize), "Invalid extent size!");

		// Once we get to this point, the program considers the extent freed,
		// so we can safely remove it from the emap before locking.
		emap.clear(e);

		uint n = 0;
		if (!e.isHuge()) {
			assert(e.hpd.address is alignDown(e.addr, HugePageSize),
			       "Invalid hpd!");

			n = ((cast(size_t) e.addr) / PageSize) % PageCount;
		}

		uint pages = modUp(e.size / PageSize, PageCount) & uint.max;

		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Allocator*) &this).freePagesImpl(e, n, pages);
	}

private:
	Extent* allocPagesImpl(shared(Arena)* arena, uint pages, ulong mask,
	                       bool is_slab, ubyte sizeClass) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto e = getOrAllocateExtent(arena);
		if (e is null) {
			return null;
		}

		auto hpd = extractHPD(&arena.base, pages, mask);
		if (hpd is null) {
			unusedExtents.insert(e);
			return null;
		}

		auto n = hpd.reserve(pages);
		if (!hpd.full) {
			registerHPD(hpd);
		}

		auto addr = hpd.address + n * PageSize;
		auto size = pages * PageSize;

		return e.at(addr, size, hpd, is_slab, sizeClass);
	}

	HugePageDescriptor* extractHPD(shared(Base)* base, uint pages, ulong mask) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto acfilter = filter & mask;
		if (acfilter == 0) {
			return allocateHPD(base);
		}

		import sdc.intrinsics;
		auto index = countTrailingZeros(acfilter);
		auto hpd = heaps[index].pop();
		filter &= ~(ulong(heaps[index].empty) << index);

		return hpd;
	}

	Extent* allocHugeImpl(shared(Arena)* arena, uint pages, uint extraPages) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto e = getOrAllocateExtent(arena);
		if (e is null) {
			return null;
		}

		auto hpd = allocateHPD(&arena.base, extraPages);
		if (hpd is null) {
			unusedExtents.insert(e);
			return null;
		}

		auto n = hpd.reserve(pages);
		assert(n == 0, "Unexpected page allocated!");

		if (!hpd.full) {
			registerHPD(hpd);
		}

		auto leadSize = extraPages * HugePageSize;
		auto addr = hpd.address - leadSize;
		auto size = leadSize + pages * PageSize;

		return e.at(addr, size, hpd);
	}

	auto getOrAllocateExtent(shared(Arena)* arena) {
		auto e = unusedExtents.pop();
		if (e !is null) {
			return e;
		}

		auto slot = arena.base.allocSlot();
		if (slot.address is null) {
			return null;
		}

		return Extent.fromSlot(cast(Arena*) arena, slot);
	}

	HugePageDescriptor* allocateHPD(shared(Base)* base, uint extraPages = 0) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto hpd = unusedHPDs.pop();
		if (hpd is null) {
			static assert(HugePageDescriptor.sizeof <= MetadataSlotSize,
			              "Unexpected HugePageDescriptor size!");

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
				regionAllocator.release(e.addr, count);
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

		auto ptr = alignDown(e.addr, HugePageSize);
		uint pages = (alignUp(e.size, HugePageSize) / HugePageSize) & uint.max;
		regionAllocator.release(ptr, pages);

		unusedHPDs.insert(hpd);
	}
}

unittest allocLarge {
	import d.gc.arena;
	Arena arena;

	auto base = &arena.base;
	scope(exit) base.clear();

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	shared Allocator allocator;
	allocator.regionAllocator = &regionAllocator;

	import d.gc.emap;
	static shared ExtentMap emap;
	emap.tree.base = base;
	allocator.emap = &emap;

	auto e0 = allocator.allocPages(&arena, 1);
	assert(e0 !is null);
	assert(e0.size == PageSize);
	auto pd0 = emap.lookup(e0.addr);
	assert(pd0.extent is e0);

	auto e1 = allocator.allocPages(&arena, 2);
	assert(e1 !is null);
	assert(e1.size == 2 * PageSize);
	assert(e1.addr is e0.addr + e0.size);
	auto pd1 = emap.lookup(e1.addr);
	assert(pd1.extent is e1);

	auto e0Addr = e0.addr;
	allocator.freePages(e0);
	auto pdf = emap.lookup(e0.addr);
	assert(pdf.extent is null);

	// Do not reuse the free slot is there is no room.
	auto e2 = allocator.allocPages(&arena, 3);
	assert(e2 !is null);
	assert(e2.size == 3 * PageSize);
	assert(e2.addr is e1.addr + e1.size);
	auto pd2 = emap.lookup(e2.addr);
	assert(pd2.extent is e2);

	// But do reuse that free slot if there isn't.
	auto e3 = allocator.allocPages(&arena, 1);
	assert(e3 !is null);
	assert(e3.size == PageSize);
	assert(e3.addr is e0Addr);
	auto pd3 = emap.lookup(e3.addr);
	assert(pd3.extent is e3);

	// Free everything.
	allocator.freePages(e1);
	allocator.freePages(e2);
	allocator.freePages(e3);
}

unittest allocHuge {
	import d.gc.arena;
	Arena arena;

	auto base = &arena.base;
	scope(exit) base.clear();

	import d.gc.region;
	shared RegionAllocator regionAllocator;
	regionAllocator.base = base;

	shared Allocator allocator;
	allocator.regionAllocator = &regionAllocator;

	import d.gc.emap;
	static shared ExtentMap emap;
	emap.tree.base = base;
	allocator.emap = &emap;

	enum uint PageCount = Allocator.PageCount;
	enum uint AllocSize = PageCount + 1;

	// Allocate a huge extent.
	auto e0 = allocator.allocPages(&arena, AllocSize);
	assert(e0 !is null);
	assert(e0.size == AllocSize * PageSize);
	auto pd0 = emap.lookup(e0.addr);
	assert(pd0.extent is e0);

	// Free the huge extent.
	auto e0Addr = e0.addr;
	allocator.freePages(e0);

	// Reallocating the same run will yield the same memory back.
	e0 = allocator.allocPages(&arena, AllocSize);
	assert(e0 !is null);
	assert(e0.addr is e0Addr);
	assert(e0.size == AllocSize * PageSize);
	pd0 = emap.lookup(e0.addr);
	assert(pd0.extent is e0);

	// Allocate one page on the borrowed huge page.
	auto e1 = allocator.allocPages(&arena, 1);
	assert(e1 !is null);
	assert(e1.size == PageSize);
	assert(e1.addr is e0.addr + e0.size);
	auto pd1 = emap.lookup(e1.addr);
	assert(pd1.extent is e1);

	// Now, freeing the huge extent will leave a page behind.
	allocator.freePages(e0);

	// Allocating another huge extent will use a new range.
	auto e2 = allocator.allocPages(&arena, AllocSize);
	assert(e2 !is null);
	assert(e2.addr is alignUp(e1.addr, HugePageSize));
	assert(e2.size == AllocSize * PageSize);
	auto pd2 = emap.lookup(e2.addr);
	assert(pd2.extent is e2);

	// Allocating new small extents fill the borrowed page.
	auto e3 = allocator.allocPages(&arena, 1);
	assert(e3 !is null);
	assert(e3.addr is alignDown(e1.addr, HugePageSize));
	assert(e3.size == PageSize);
	auto pd3 = emap.lookup(e3.addr);
	assert(pd3.extent is e3);

	// But allocating just the right size will reuse the region.
	auto e4 = allocator.allocPages(&arena, PageCount);
	assert(e4 !is null);
	assert(e4.addr is e0Addr);
	assert(e4.size == PageCount * PageSize);
	auto pd4 = emap.lookup(e4.addr);
	assert(pd4.extent is e4);

	// Free everything.
	allocator.freePages(e1);
	allocator.freePages(e2);
	allocator.freePages(e3);
	allocator.freePages(e4);
}