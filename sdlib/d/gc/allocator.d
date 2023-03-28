module d.gc.allocator;

import d.gc.allocclass;
import d.gc.arena;
import d.gc.base;
import d.gc.extent;
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

	ulong filter;

	enum PageCount = HugePageDescriptor.PageCount;
	enum HeapCount = getAllocClass(PageCount) + 1;
	static assert(HeapCount <= 64, "Too many heaps to fit in the filter!");

	import d.gc.heap;
	Heap!(HugePageDescriptor, generationHPDCmp)[HeapCount] heaps;

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

	Extent* allocPages(shared(Arena)* arena, uint pages) shared {
		// FIXME: Overload resolution doesn't cast this properly.
		return allocPages(arena, pages, false, ubyte(0));
	}

	Extent* allocPages(shared(Arena)* arena, uint pages,
	                   ubyte sizeClass) shared {
		return allocPages(arena, pages, true, sizeClass);
	}

	void freePages(Extent* e) shared {
		assert(isAligned(e.addr, PageSize), "Invalid extent addr!");
		assert(isAligned(e.size, PageSize), "Invalid extent size!");
		assert(e.hpd !is null, "Missing hpd!");
		assert(e.hpd.address is alignDown(e.addr, HugePageSize),
		       "Invalid hpd!");

		uint n = ((cast(size_t) e.addr) / PageSize) % PageCount;
		uint pages = (e.size / PageSize) & uint.max;

		// Once we get to this point, the program considers the extent freed,
		// so we can safely remove it from the emap before locking.
		emap.clear(e);

		// FIXME: Save the extent for resuse later instead of leaking.

		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Allocator*) &this).freePagesImpl(e.hpd, n, pages);
	}

private:
	Extent* allocPagesImpl(shared(Arena)* arena, uint pages, ulong mask,
	                       bool is_slab, ubyte sizeClass) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto base = &arena.base;
		auto e = base.allocExtent();
		if (e is null) {
			return null;
		}

		auto hpd = extractHPD(base, pages, mask);
		auto n = hpd.reserve(pages);
		if (!hpd.full) {
			registerHPD(hpd);
		}

		auto addr = hpd.address + n * PageSize;
		auto size = pages * PageSize;

		*e = Extent(cast(Arena*) arena, addr, size, hpd, is_slab, sizeClass);
		return e;
	}

	void freePagesImpl(HugePageDescriptor* hpd, uint n, uint pages) {
		assert(mutex.isHeld(), "Mutex not held!");

		if (!hpd.full) {
			auto index = getFreeSpaceClass(hpd.longestFreeRange);
			heaps[index].remove(hpd);
			filter &= ~(ulong(heaps[index].empty) << index);
		}

		hpd.release(n, pages);
		registerHPD(hpd);
	}

	HugePageDescriptor* extractHPD(shared(Base)* base, uint pages, ulong mask) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto acfilter = filter & mask;
		if (acfilter == 0) {
			return regionAllocator.extract(base);
		}

		import sdc.intrinsics;
		auto index = countTrailingZeros(acfilter);
		auto hpd = heaps[index].pop();
		filter &= ~(ulong(heaps[index].empty) << index);

		return hpd;
	}

	void registerHPD(HugePageDescriptor* hpd) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(!hpd.full, "HPD is full!");

		auto index = getFreeSpaceClass(hpd.longestFreeRange);
		heaps[index].insert(hpd);
		filter |= ulong(1) << index;
	}
}

unittest allocfree {
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
	assert(e3.addr is e0.addr);
	auto pd3 = emap.lookup(e3.addr);
	assert(pd3.extent is e3);
}
