module d.gc.allocator;

import d.gc.extent;
import d.gc.hpd;
import d.gc.spec;
import d.gc.util;

struct Allocator {
private:
	import d.gc.base;
	shared(Base)* base;

	import d.gc.hpa;
	shared(HugePageAllocator)* hpa;

	import d.sync.mutex;
	Mutex mutex;

	ulong filter;

	enum PageCount = HugePageDescriptor.PageCount;
	enum HeapCount = getAllocClass(PageCount) + 1;
	static assert(HeapCount <= 64, "Too many heaps to fit in the filter!");

	import d.gc.heap;
	Heap!(HugePageDescriptor, generationHPDCmp)[HeapCount] heaps;

public:
	Extent* allocPages(uint pages) shared {
		assert(pages > 0 && pages <= PageCount, "Invalid page count!");
		auto mask = ulong.max << getAllocClass(pages);

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(Allocator*) &this).allocPagesImpl(pages, mask);
	}

	void freePages(Extent* e) shared {
		assert(isAligned(e.addr, PageSize), "Invalid extent addr!");
		assert(isAligned(e.size, PageSize), "Invalid extent size!");
		assert(e.hpd !is null, "Missing hpd!");
		assert(e.hpd.address is alignDown(e.addr, HugePageSize),
		       "Invalid hpd!");

		uint n = ((cast(size_t) e.addr) / PageSize) % PageCount;
		uint pages = (e.size / PageSize) & uint.max;

		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(Allocator*) &this).freePagesImpl(e, n, pages);
	}

private:
	Extent* allocPagesImpl(uint pages, ulong mask) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto e = base.allocExtent();
		if (e is null) {
			return null;
		}

		auto hpd = extractHPD(pages, mask);
		auto n = hpd.reserve(pages);
		if (!hpd.full) {
			registerHPD(hpd);
		}

		e.addr = hpd.address + n * PageSize;
		e.size = pages * PageSize;
		e.hpd = hpd;

		return e;
	}

	void freePagesImpl(Extent* e, uint n, uint pages) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto hpd = e.hpd;

		if (!hpd.full) {
			auto index = getFreeSpaceClass(hpd.longestFreeRange);
			heaps[index].remove(hpd);
			filter &= ~(ulong(heaps[index].empty) << index);
		}

		hpd.release(n, pages);
		registerHPD(hpd);
	}

	HugePageDescriptor* extractHPD(uint pages, ulong mask) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto acfilter = filter & mask;
		if (acfilter == 0) {
			return hpa.extract(base);
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
	import d.gc.base;
	shared Base base;
	scope(exit) base.clear();

	import d.gc.hpa;
	shared HugePageAllocator hpa;
	hpa.base = &base;

	shared Allocator allocator;
	allocator.base = &base;
	allocator.hpa = &hpa;

	auto e0 = allocator.allocPages(1);
	assert(e0 !is null);
	assert(e0.size == PageSize);

	auto e1 = allocator.allocPages(2);
	assert(e1 !is null);
	assert(e1.size == 2 * PageSize);
	assert(e1.addr is e0.addr + e0.size);

	allocator.freePages(e0);

	// Do not reuse the free slot is there is no room.
	auto e2 = allocator.allocPages(3);
	assert(e2 !is null);
	assert(e2.size == 3 * PageSize);
	assert(e2.addr is e1.addr + e1.size);

	// But do reuse that free slot if there isn't.
	auto e3 = allocator.allocPages(1);
	assert(e3 !is null);
	assert(e3.size == PageSize);
	assert(e3.addr is e0.addr);
}

ubyte getAllocClass(uint pages) {
	if (pages <= 8) {
		auto ret = pages - 1;

		assert(pages == 0 || ret < ubyte.max);
		return ret & 0xff;
	}

	import d.gc.util;
	auto shift = log2floor(pages - 1) - 2;
	auto mod = (pages - 1) >> shift;
	auto ret = 4 * shift + mod;

	assert(ret < ubyte.max);
	return ret & 0xff;
}

unittest getAllocClass {
	import d.gc.bin;
	assert(getAllocClass(0) == 0xff);

	uint[] boundaries =
		[1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 20, 24, 28, 32, 40, 48, 56, 64,
		 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512];

	uint ac = 0;
	uint s = 1;
	foreach (b; boundaries) {
		while (s <= b) {
			assert(getAllocClass(s) == ac);
			s++;
		}

		ac++;
	}
}

ubyte getFreeSpaceClass(uint pages) {
	return (getAllocClass(pages + 1) - 1) & 0xff;
}

unittest getFreeSpaceClass {
	import d.gc.bin;
	assert(getFreeSpaceClass(0) == 0xff);

	uint[] boundaries =
		[1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 20, 24, 28, 32, 40, 48, 56, 64,
		 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512];

	uint fc = -1;
	uint s = 1;
	foreach (b; boundaries) {
		while (s < b) {
			assert(getFreeSpaceClass(s) == fc);
			s++;
		}

		fc++;
	}
}
