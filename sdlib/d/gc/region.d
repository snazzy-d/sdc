module d.gc.region;

import d.gc.allocclass;
import d.gc.base;
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
shared(RegionAllocator)* gDataRegionAllocator() {
	static shared RegionAllocator regionAllocator;

	if (regionAllocator.base is null) {
		regionAllocator.base = &gBase;
	}

	return &regionAllocator;
}

@property
shared(RegionAllocator)* gPointerRegionAllocator() {
	static shared RegionAllocator regionAllocator;

	if (regionAllocator.base is null) {
		regionAllocator.base = &gBase;
	}

	return &regionAllocator;
}

struct RegionAllocator {
private:
	shared(Base)* base;

	import d.sync.mutex;
	Mutex mutex;

	ulong nextEpoch;

	// Free regions we can allocate from.
	ClassTree regionsByClass;
	RangeTree regionsByRange;

	// Unused region objects.
	Heap!(Region, unusedRegionCmp) unusedRegions;

public:
	bool acquire(HugePageDescriptor* hpd, uint extraHugePages = 0) shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(RegionAllocator*) &this).acquireImpl(hpd, extraHugePages);
	}

	void release(HugePageDescriptor* hpd) shared {
		// FIXME: assert the hpd is not borrowed.
		assert(hpd.empty, "HPD is not empty!");

		release(hpd.address, 1);
	}

	void release(void* ptr, uint pages) shared {
		assert(pages > 0, "Invalid number of pages!");

		mutex.lock();
		scope(exit) mutex.unlock();

		(cast(RegionAllocator*) &this).releaseImpl(ptr, pages);
	}

private:
	bool acquireImpl(HugePageDescriptor* hpd, uint extraHugePages = 0) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto totalHugePages = extraHugePages + 1;

		Region rr;
		rr.allocClass = getAllocClass(totalHugePages);

		auto r = regionsByClass.extractBestFit(&rr);
		if (r is null) {
			r = refillAddressSpace(extraHugePages);
			if (r is null) {
				return false;
			}
		} else {
			regionsByRange.remove(r);
		}

		assert(r.address !is null && isAligned(r.address, HugePageSize),
		       "Invalid address!");
		assert(r.size >= HugePageSize && isAligned(r.size, HugePageSize),
		       "Invalid size!");
		assert(r.size > extraHugePages * HugePageSize,
		       "Insuffiscient address space!");

		auto ptr = r.address;
		auto extraSize = extraHugePages * HugePageSize;
		hpd.at(ptr + extraSize, nextEpoch++);

		auto allocSize = totalHugePages * HugePageSize;
		auto newSize = r.size - allocSize;
		if (newSize == 0) {
			unusedRegions.insert(r);
			return true;
		}

		r.at(ptr + allocSize, newSize);
		registerRegion(r);
		return true;
	}

	void releaseImpl(void* ptr, uint pages) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto r = getOrAllocateRegion();
		r.at(ptr, pages * HugePageSize);
		registerRegion(r);
	}

	void registerRegion(Region* toRegister) {
		Region r = *toRegister;
		unusedRegions.insert(toRegister);

		// First, merge adjacent ranges.
		while (true) {
			auto adjacent = regionsByRange.extract(&r);
			if (adjacent is null) {
				break;
			}

			r.merge(adjacent);
			regionsByClass.remove(adjacent);
			unusedRegions.insert(adjacent);
		}

		toRegister = unusedRegions.pop();

		assert(toRegister !is null);
		toRegister.clone(&r);
		regionsByClass.insert(toRegister);
		regionsByRange.insert(toRegister);
	}

	Region* refillAddressSpace(uint extraHugePages) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto r = getOrAllocateRegion();
		if (r is null) {
			return null;
		}

		auto pages = alignUp(extraHugePages + 1, RefillSize / HugePageSize);
		auto size = pages * HugePageSize;

		auto ptr = base.reserveAddressSpace(size, HugePageSize);
		if (ptr is null) {
			unusedRegions.insert(r);
			return null;
		}

		return r.at(ptr, size);
	}

	Region* getOrAllocateRegion() {
		auto r = unusedRegions.pop();
		if (r !is null) {
			return r;
		}

		auto slot = base.allocSlot();
		if (slot.address is null) {
			return null;
		}

		static assert(ExtentSize / Region.sizeof == 2,
		              "Unexpected Region size!");

		auto r0 = Region.fromSlot(slot, 0);
		auto r1 = Region.fromSlot(slot, 1);

		unusedRegions.insert(r1);
		return r0;
	}
}

unittest acquire_release {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	// To snoop in.
	auto ra = cast(RegionAllocator*) &regionAllocator;

	ulong expectedEpoch = 0;
	HugePageDescriptor hpd0;

	assert(regionAllocator.acquire(&hpd0));
	assert(hpd0.epoch == expectedEpoch++);

	foreach (i; 1 .. RefillSize / HugePageSize) {
		HugePageDescriptor hpd;
		assert(regionAllocator.acquire(&hpd));
		assert(hpd.epoch == expectedEpoch++);
		assert(hpd.address is hpd0.address + i * HugePageSize);
	}

	foreach (i; 5 .. RefillSize / HugePageSize) {
		HugePageDescriptor hpd;
		hpd.at(hpd0.address + i * HugePageSize, 0);
		regionAllocator.release(&hpd);
	}

	{
		auto r = ra.regionsByClass.extractAny();
		scope(exit) ra.regionsByClass.insert(r);

		assert(r.address is hpd0.address + 5 * HugePageSize);
		assert(r.size == RefillSize - 5 * HugePageSize);
	}

	foreach (i; 0 .. 5) {
		HugePageDescriptor hpd;
		hpd.at(hpd0.address + i * HugePageSize, 0);
		regionAllocator.release(&hpd);
	}

	{
		auto r = ra.regionsByClass.extractAny();
		scope(exit) ra.regionsByClass.insert(r);

		assert(r.address is hpd0.address);
		assert(r.size == RefillSize);
	}
}

unittest extra_pages {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	HugePageDescriptor hpd0;
	assert(regionAllocator.acquire(&hpd0));

	HugePageDescriptor hpd1;
	assert(regionAllocator.acquire(&hpd1, 1));
	assert(hpd1.address is hpd0.address + 2 * HugePageSize);

	HugePageDescriptor hpd2;
	assert(regionAllocator.acquire(&hpd2, 5));
	assert(hpd2.address is hpd1.address + 6 * HugePageSize);

	// Release 3 huge pages. We now have 2 regions.
	regionAllocator.release(&hpd0);
	regionAllocator.release(hpd0.address + HugePageSize, 2);

	// Too big too fit.
	HugePageDescriptor hpd3;
	assert(regionAllocator.acquire(&hpd3, 3));
	assert(hpd3.address is hpd2.address + 4 * HugePageSize);

	// Small enough, so we reuse freed regions.
	HugePageDescriptor hpd4;
	assert(regionAllocator.acquire(&hpd4, 2));
	assert(hpd4.address is hpd0.address + 2 * HugePageSize);
}

unittest enormous {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	enum HugePages = 2048;
	enum ExtraPages = HugePages - 1;

	HugePageDescriptor hpd0;
	assert(regionAllocator.acquire(&hpd0, ExtraPages));
	regionAllocator
		.release(hpd0.address - ExtraPages * HugePageSize, HugePages);
}

struct Region {
	void* address;
	size_t size;

	ubyte allocClass;
	ubyte generation;

	struct UsedLinks {
		ClassNode rbClass;
		RangeNode rbRange;
	}

	union Links {
		PHNode phnode;
		UsedLinks usedLinks;
	}

	Links _links;

	this(void* ptr, size_t size, ubyte generation = 0) {
		assert(isAligned(ptr, HugePageSize), "Invalid ptr alignment!");
		assert(isAligned(size, HugePageSize), "Invalid size!");

		address = ptr;
		this.size = size;
		this.generation = generation;

		allocClass = getFreeSpaceClass(hugePageCount);
	}

public:
	Region* at(void* ptr, size_t size) {
		this = Region(ptr, size, generation);
		return &this;
	}

	static fromSlot(Base.Slot slot, uint i) {
		// FIXME: in contract
		assert(slot.address !is null, "Slot is empty!");
		assert(i < ExtentSize / Region.sizeof, "Invalid index!");

		auto r = (cast(Region*) slot.address) + i;
		*r = Region(null, 0, slot.generation);
		return r;
	}

	Region* clone(Region* r) {
		address = r.address;
		this.size = r.size;
		this.allocClass = r.allocClass;

		assert(allocClass == getFreeSpaceClass(hugePageCount),
		       "Invalid alloc class!");

		return &this;
	}

	Region* merge(Region* r) {
		assert(address is (r.address + r.size) || r.address is (address + size),
		       "Regions are not adjacent!");

		import d.gc.util;
		auto a = min(address, r.address);
		return at(a, size + r.size);
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
	size_t hugePageCount() const {
		return size / HugePageSize;
	}
}

ptrdiff_t addrRangeRegionCmp(Region* lhs, Region* rhs) {
	auto lstart = cast(size_t) lhs.address;
	auto rstart = cast(size_t) rhs.address;

	auto lend = lstart + lhs.size;
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
	static assert(LgAddressSpace <= 56, "Address space too large!");

	auto l = ulong(lhs.allocClass) << 56;
	auto r = ulong(rhs.allocClass) << 56;

	l |= cast(size_t) lhs.address;
	r |= cast(size_t) rhs.address;

	return (l > r) - (l < r);
}

ptrdiff_t unusedRegionCmp(Region* lhs, Region* rhs) {
	static assert(LgAddressSpace <= 56, "Address space too large!");

	auto l = ulong(lhs.generation) << 56;
	auto r = ulong(rhs.generation) << 56;

	l |= cast(size_t) lhs;
	r |= cast(size_t) rhs;

	return (l > r) - (l < r);
}
