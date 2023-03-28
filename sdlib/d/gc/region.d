module d.gc.region;

import d.gc.allocclass;
import d.gc.heap;
import d.gc.hpd;
import d.gc.rbtree;

import d.gc.spec;
import d.gc.util;

alias ClassTree = RBTree!(Region, classAddrRegionCmp, "rbClass");
alias RangeTree = RBTree!(Region, addrRangeRegionCmp, "rbRange");

alias ClassNode = rbtree.Node!(Region, "rbClass");
alias RangeNode = rbtree.Node!(Region, "rbRange");
alias PHNode = heap.Node!Region;

// Reserve memory in blocks of 1GB.
enum RefillSize = 1024 * 1024 * 1024;

@property
shared(RegionAllocator)* gRegionAllocator() {
	static shared RegionAllocator regionAllocator;

	if (regionAllocator.base is null) {
		import d.gc.base;
		regionAllocator.base = &gBase;
	}

	return &regionAllocator;
}

struct RegionAllocator {
private:
	import d.gc.base;
	shared(Base)* base;

	import d.sync.mutex;
	Mutex mutex;

	ulong nextGeneration;

	// Free regions we can allocate from.
	ClassTree regionsByClass;
	RangeTree regionsByRange;

	// Unused region objects.
	Heap!(Region, unusedRegionCmp) unusedRegions;

public:
	HugePageDescriptor* extract(shared(Base)* allocatorBase) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(RegionAllocator*) &this).extractImpl(allocatorBase);
	}

private:
	HugePageDescriptor* extractImpl(shared(Base)* allocatorBase) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto rr = Region(null, HugePageSize);
		auto r = regionsByClass.extractBestFit(&rr);

		if (r is null) {
			r = refillAddressSpace();
			if (r is null) {
				return null;
			}
		} else {
			regionsByRange.remove(r);
		}

		assert(r.address !is null && isAligned(r.address, HugePageSize),
		       "Invalid address!");
		assert(r.size >= HugePageSize && isAligned(r.size, HugePageSize),
		       "Invalid size!");

		scope(success) {
			if (r.size > 0) {
				regionsByClass.insert(r);
				regionsByRange.insert(r);
			} else {
				unusedRegions.insert(r);
			}
		}

		auto hpd = allocatorBase.allocHugePageDescriptor();
		if (hpd is null) {
			return null;
		}

		*hpd = HugePageDescriptor(r.address, nextGeneration++);
		*r = Region(r.address + HugePageSize, r.size - HugePageSize);
		return hpd;
	}

	Region* refillAddressSpace() {
		assert(mutex.isHeld(), "Mutex not held!");

		auto r = getOrAllocateRegion();
		if (r is null) {
			return null;
		}

		auto ptr = base.reserveAddressSpace(RefillSize, HugePageSize);
		if (ptr is null) {
			unusedRegions.insert(r);
			return null;
		}

		*r = Region(ptr, RefillSize);
		return r;
	}

	Region* getOrAllocateRegion() {
		auto r = unusedRegions.pop();
		if (r !is null) {
			return r;
		}

		import d.gc.extent;
		static assert(Extent.Size / Region.sizeof == 2,
		              "Unexpected Region size!");
		r = cast(Region*) base.allocExtent();

		unusedRegions.insert(r + 1);
		return r;
	}
}

unittest extract {
	import d.gc.base;
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	ulong expectedGeneration = 0;
	auto hpd0 = regionAllocator.extract(&base);
	assert(hpd0.generation == expectedGeneration++);

	foreach (i; 1 .. RefillSize / HugePageSize) {
		auto hpd = regionAllocator.extract(&base);
		assert(hpd.generation == expectedGeneration++);
		assert(hpd.address is hpd0.address + i * HugePageSize);
	}
}

struct Region {
	void* address;
	size_t data;

	struct UsedLinks {
		ClassNode rbClass;
		RangeNode rbRange;
	}

	union Links {
		PHNode phnode;
		UsedLinks usedLinks;
	}

	Links _links;

public:
	this(void* ptr, size_t size) {
		assert(isAligned(ptr, HugePageSize), "Invalid ptr alignment!");
		assert(isAligned(size, HugePageSize), "Invalid size!");

		address = ptr;
		data = size;
		data |= getFreeSpaceClass(hugePageCount);
	}

	@property
	ref PHNode phnode() {
		return _links.phnode;
	}

	@property
	ref ClassNode rbClass() {
		return _links.usedLinks.rbClass;
	}

	@property
	ref RangeNode rbRange() {
		return _links.usedLinks.rbRange;
	}

	@property
	ubyte allocClass() const {
		return data & 0xff;
	}

	@property
	size_t hugePageCount() const {
		return data / HugePageSize;
	}

	@property
	size_t size() const {
		return hugePageCount * HugePageSize;
	}
}

ptrdiff_t addrRangeRegionCmp(Region* lhs, Region* rhs) {
	auto lstart = cast(size_t) lhs.address;
	auto lend = lstart + lhs.size;
	auto rstart = cast(size_t) rhs.address;
	auto rend = rstart + rhs.size;

	return (lstart > rend) - (lend < rstart);
}

unittest rangeTree {
	import d.gc.rbtree;
	RBTree!(Region, addrRangeRegionCmp, "rbRange") regionByRange;

	auto base = cast(void*) 0x456789a00000;
	auto r0 = Region(base, HugePageSize);
	auto r1 = Region(base + HugePageSize, HugePageSize);
	auto r2 = Region(base + 2 * HugePageSize, HugePageSize);

	regionByRange.insert(&r0);

	assert(regionByRange.extract(&r2) is null);
	regionByRange.insert(&r2);

	assert(regionByRange.extract(&r1) is &r0);
	assert(regionByRange.extract(&r1) is &r2);
	assert(regionByRange.extract(&r1) is null);
}

ptrdiff_t classAddrRegionCmp(Region* lhs, Region* rhs) {
	static assert(LgAddressSpace <= 56, "");

	auto l = ulong(lhs.allocClass) << 56;
	auto r = ulong(rhs.allocClass) << 56;

	l |= cast(size_t) lhs.address;
	r |= cast(size_t) rhs.address;

	return (l > r) - (l < r);
}

ptrdiff_t unusedRegionCmp(Region* lhs, Region* rhs) {
	auto l = cast(size_t) lhs;
	auto r = cast(size_t) rhs;

	return (l > r) - (l < r);
}
