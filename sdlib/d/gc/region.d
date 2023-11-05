module d.gc.region;

import d.gc.allocclass;
import d.gc.base;
import d.gc.heap;
import d.gc.hpd;
import d.gc.rbtree;

import d.gc.spec;
import d.gc.util;

alias ClassTree = RBTree!(Region, classDirtAddrRegionCmp, "rbClass");
alias RangeTree = RBTree!(Region, addrRangeRegionCmp, "rbRange");
alias DirtTree = RBTree!(Region, dirtClassAddrRegionCmp, "rbDirt");
alias DirtAgeTree = RBTree!(Region, dirtAgeAddrRegionCmp, "rbDirtAge");

alias ClassNode = rbtree.Node!(Region, "rbClass");
alias RangeNode = rbtree.Node!(Region, "rbRange");
alias DirtNode = rbtree.Node!(Region, "rbDirt");
alias DirtAgeNode = rbtree.Node!(Region, "rbDirtAge");
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
	size_t dirtyPages = 0;
	size_t dirtEpoch = 0;

	// Free regions we can allocate from.
	ClassTree regionsByClass;
	RangeTree regionsByRange;
	DirtTree regionsByDirt;

	// Dirty page aging
	DirtAgeTree regionsByDirtAge;

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

	@property
	size_t dirtyPageCount() shared {
		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(RegionAllocator*) &this).dirtyPages;
	}

	uint purgeDirtyPages(uint pages) shared {
		assert(pages > 0, "Invalid number of pages!");

		mutex.lock();
		scope(exit) mutex.unlock();

		return (cast(RegionAllocator*) &this).purgeDirtyPagesImpl(pages);
	}

private:
	bool acquireImpl(HugePageDescriptor* hpd, uint extraHugePages = 0) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto totalHugePages = extraHugePages + 1;

		Region rr;
		rr.allocClass = getAllocClass(totalHugePages);
		rr.dirtClass = 255;

		// Allocate from the longest dirty run, if possible:
		auto r = regionsByDirt.extractBestFit(&rr);
		if (r !is null) {
			if (totalHugePages <= r.hugePageCount) {
				regionsByClass.remove(r);
			} else {
				regionsByDirt.insert(r);
				r = null;
			}
		}

		// Otherwise, allocate best fit with the most dirty pages:
		if (r is null) {
			r = regionsByClass.extractBestFit(&rr);
		}

		// If neither succeeded:
		if (r is null) {
			r = refillAddressSpace(extraHugePages);
			if (r is null) {
				return false;
			}
		} else {
			regionsByRange.remove(r);
			unregisterDirt(r);
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
			dirtyPages -= r.dirtyPageCount;
			return true;
		}

		// Remnant segment of the used region may be partially dirty:
		auto regionDirtySize = r.dirtySize;
		auto unusedDirtySize =
			allocSize > regionDirtySize ? 0 : regionDirtySize - allocSize;
		r.at(ptr + allocSize, newSize, unusedDirtySize);
		auto reusedDirtyPages =
			(regionDirtySize - unusedDirtySize) / HugePageSize;
		dirtyPages -= reusedDirtyPages;
		registerRegion(r);
		return true;
	}

	uint purgeDirtyPagesImpl(uint pages) {
		assert(mutex.isHeld(), "Mutex not held!");

		uint purgedPages = 0;
		Region rr;
		rr.dirtEpoch = 0;

		while (purgedPages < pages) {
			auto r = regionsByDirtAge.extractBestFit(&rr);
			if (r is null) {
				break;
			}

			auto regionDirtyPages = cast(uint) r.dirtyPageCount;
			auto toPurge = min(pages, regionDirtyPages);
			purgeDirtyRegionPages(r, toPurge);
			purgedPages += toPurge;
		}

		return purgedPages;
	}

	void purgeDirtyRegionPages(Region* r, uint pages) {
		assert(mutex.isHeld(), "Mutex not held!");
		assert(r.dirtyPageCount >= pages,
		       "Region does not have requested number of dirty pages!");

		auto purgeSize = pages * HugePageSize;
		auto remnantDirt = r.dirtySize - purgeSize;
		base.purgeAddressSpace(r.address + remnantDirt, purgeSize);
		// Reducing dirt could make region mergeable with adjacent regions:
		unregisterDirt(r);
		regionsByRange.remove(r);
		regionsByClass.remove(r);
		r.setDirt(remnantDirt);
		registerRegion(r);
		dirtyPages -= pages;
	}

	void unregisterDirt(Region* r) {
		regionsByDirt.extract(r);
		regionsByDirtAge.extract(r);
	}

	void registerDirt(Region* r) {
		if (r.hasDirt) {
			regionsByDirt.insert(r);
			regionsByDirtAge.insert(r);
		}
	}

	void releaseImpl(void* ptr, uint pages) {
		assert(mutex.isHeld(), "Mutex not held!");

		auto r = getOrAllocateRegion();
		auto size = pages * HugePageSize;
		// Released pages are considered dirty:
		dirtyPages += pages;
		r.at(ptr, size, size, dirtEpoch++);
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
			unregisterDirt(adjacent);
			unusedRegions.insert(adjacent);
		}

		toRegister = unusedRegions.pop();

		assert(toRegister !is null);
		toRegister.clone(&r);
		regionsByClass.insert(toRegister);
		registerDirt(toRegister);
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

		// Newly allocated pages are considered clean:
		return r.at(ptr, size, 0);
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

		static assert(Region.sizeof <= ExtentSize, "Unexpected Region size!");

		return Region.fromSlot(slot);
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

	assert(regionAllocator.dirtyPageCount == 0);
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
		assert(regionAllocator.dirtyPageCount == i - 4);
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
		assert(regionAllocator.dirtyPageCount == i + 508);
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
	assert(regionAllocator.dirtyPageCount == 0);
	regionAllocator.release(&hpd0);
	assert(regionAllocator.dirtyPageCount == 1);
	regionAllocator.release(hpd0.address + HugePageSize, 2);
	assert(regionAllocator.dirtyPageCount == 3);

	// Too big too fit.
	HugePageDescriptor hpd3;
	assert(regionAllocator.acquire(&hpd3, 3));
	assert(hpd3.address is hpd2.address + 4 * HugePageSize);
	assert(regionAllocator.dirtyPageCount == 3);

	// Small enough, so we reuse freed regions.
	HugePageDescriptor hpd4;
	assert(regionAllocator.acquire(&hpd4, 2));
	assert(hpd4.address is hpd0.address + 2 * HugePageSize);
	assert(regionAllocator.dirtyPageCount == 0);
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
	size_t dirtySize;
	size_t dirtEpoch;

	ubyte allocClass;
	ubyte dirtClass;
	ubyte generation;

	struct UsedLinks {
		ClassNode rbClass;
		DirtNode rbDirt;
		DirtAgeNode rbDirtAge;
		RangeNode rbRange;
	}

	union Links {
		PHNode phnode;
		UsedLinks usedLinks;
	}

	Links _links;

	this(void* ptr, size_t size, ubyte generation = 0, size_t dirtySize = 0,
	     size_t dirtEpoch = 0) {
		assert(isAligned(ptr, HugePageSize), "Invalid ptr alignment!");
		assert(isAligned(size, HugePageSize), "Invalid size!");
		assert(isAligned(dirtySize, HugePageSize), "Invalid dirtySize!");
		assert(dirtySize <= size, "Dirty size exceeds size!");

		address = ptr;
		this.size = size;
		this.dirtEpoch = dirtEpoch;
		this.generation = generation;

		allocClass = getFreeSpaceClass(hugePageCount);
		setDirt(dirtySize);
	}

public:
	Region* at(void* ptr, size_t size, size_t dirtySize, size_t dirtEpoch) {
		this = Region(ptr, size, generation, dirtySize, dirtEpoch);
		return &this;
	}

	Region* at(void* ptr, size_t size, size_t dirtySize) {
		return at(ptr, size, dirtySize, dirtEpoch);
	}

	static fromSlot(Base.Slot slot) {
		// FIXME: in contract
		assert(slot.address !is null, "Slot is empty!");

		auto r = cast(Region*) slot.address;
		*r = Region(null, 0, slot.generation);
		return r;
	}

	Region* clone(Region* r) {
		address = r.address;
		this.size = r.size;
		this.dirtySize = r.dirtySize;
		this.allocClass = r.allocClass;
		this.dirtClass = r.dirtClass;
		this.dirtEpoch = r.dirtEpoch;

		assert(allocClass == getFreeSpaceClass(hugePageCount),
		       "Invalid alloc class!");

		return &this;
	}

	Region* merge(Region* r) {
		auto rIsLeft = address is (r.address + r.size);
		auto rIsRight = r.address is (address + size);
		assert(rIsLeft || rIsRight, "Regions are not adjacent!");

		auto leftRegion = rIsLeft ? r : &this;
		auto rightRegion = rIsRight ? r : &this;

		// Dirt is at all times contiguous within a region, and starts at the bottom
		assert(!leftRegion.hasClean || !rightRegion.hasDirt,
		       "Merge would place dirty pages in front of clean pages !");

		return at(leftRegion.address, size + r.size, dirtySize + r.dirtySize,
		          dirtySize >= r.dirtySize ? dirtEpoch : r.dirtEpoch);
	}

	void setDirt(size_t newDirtySize) {
		dirtySize = newDirtySize;
		dirtClass = getFreeSpaceClass(dirtyPageCount);
		dirtClass++;
	}

	@property
	bool hasClean() {
		return dirtySize < size;
	}

	@property
	bool hasDirt() {
		return dirtySize > 0;
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
	ref DirtNode rbDirt() {
		return _links.usedLinks.rbDirt;
	}

	@property
	ref DirtAgeNode rbDirtAge() {
		return _links.usedLinks.rbDirtAge;
	}

	@property
	ref RangeNode rbRange() {
		return _links.usedLinks.rbRange;
	}

	@property
	size_t hugePageCount() const {
		return size / HugePageSize;
	}

	@property
	size_t dirtyPageCount() const {
		return dirtySize / HugePageSize;
	}
}

ptrdiff_t addrRangeRegionCmp(Region* lhs, Region* rhs) {
	auto lstart = cast(size_t) lhs.address;
	auto rstart = cast(size_t) rhs.address;

	auto lend = lstart + lhs.size;
	auto rend = rstart + rhs.size;

	auto cmp = (lstart > rend) - (lend < rstart);
	if (cmp != 0) {
		return cmp;
	}

	auto lr = lend == rstart;
	auto rl = rend == lstart;
	assert(!lr || !rl, "Overlapping ranges!");

	// Regions are not adjacently connected, but rather identical:
	if (!lr && !rl) {
		return 0;
	}

	// Regions are adjacently connected, and may be "equal" for purpose of merging:
	auto leftAdjacent = lr ? lhs : rhs;
	auto rightAdjacent = rl ? lhs : rhs;
	if (!leftAdjacent.hasClean || !rightAdjacent.hasDirt) {
		return 0;
	}

	// Unmergeable pair ordering (i.e. a proposed |clean|dirty| merge)
	return rl - lr;
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

unittest rangeEquality {
	import d.gc.rbtree;
	RBTree!(Region, addrRangeRegionCmp, "rbRange") regionByRange;

	auto base = cast(void*) 0x456789a00000;
	auto r0 = Region(base, 2 * HugePageSize);
	auto r1 = Region(base + 2 * HugePageSize, 2 * HugePageSize);
	auto r2 = Region(base + 4 * HugePageSize, 2 * HugePageSize);

	void setDirties(uint r0DirtyPages, uint r1DirtyPages, uint r2DirtyPages) {
		regionByRange.clear();
		regionByRange.insert(&r0);
		regionByRange.insert(&r2);
		r0.setDirt(r0DirtyPages * HugePageSize);
		r1.setDirt(r1DirtyPages * HugePageSize);
		r2.setDirt(r2DirtyPages * HugePageSize);
	}

	// r1 cannot merge with either r0 or r2
	void verifyNone(uint r0dp, uint r1dp, uint r2dp) {
		setDirties(r0dp, r1dp, r2dp);
		assert(regionByRange.extract(&r1) is null);
	}

	// r1 cannot merge with r2
	void verifyOnlyLeft(uint r0dp, uint r1dp, uint r2dp) {
		setDirties(r0dp, r1dp, r2dp);
		assert(regionByRange.extract(&r1) is &r0);
		assert(regionByRange.extract(&r1) is null);
	}

	// r1 cannot merge with r0
	void verifyOnlyRight(uint r0dp, uint r1dp, uint r2dp) {
		setDirties(r0dp, r1dp, r2dp);
		assert(regionByRange.extract(&r1) is &r2);
		assert(regionByRange.extract(&r1) is null);
	}

	// r1 can merge with either r0 or r2
	void verifyLeftAndRight(uint r0dp, uint r1dp, uint r2dp) {
		setDirties(r0dp, r1dp, r2dp);
		assert(regionByRange.extract(&r1) is &r0);
		assert(regionByRange.extract(&r1) is &r2);
		assert(regionByRange.extract(&r1) is null);
	}

	// Verify that under particular combinations of dirty page counts for r0, r1, r2,
	// r1 can be merged in the stated directions (i.e. left: r0, right: r2)
	verifyLeftAndRight(0, 0, 0);
	verifyLeftAndRight(1, 0, 0);
	verifyLeftAndRight(2, 1, 0);
	verifyLeftAndRight(2, 2, 0);
	verifyLeftAndRight(2, 2, 1);
	verifyLeftAndRight(2, 2, 2);
	verifyOnlyRight(1, 1, 0);
	verifyOnlyRight(1, 2, 0);
	verifyOnlyRight(0, 2, 0);
	verifyOnlyRight(0, 2, 1);
	verifyOnlyLeft(2, 0, 2);
	verifyOnlyLeft(0, 0, 1);
	verifyOnlyLeft(1, 0, 1);
	verifyOnlyLeft(2, 1, 1);
	verifyNone(1, 1, 1);
	verifyNone(0, 1, 1);
}

unittest rangeMerging {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;
	auto ra = cast(RegionAllocator*) &regionAllocator;

	auto baseAddress = cast(void*) 0x456789a00000;

	void* makeRegion(void* address, size_t pages, size_t dirtyPages) {
		auto r = ra.getOrAllocateRegion();
		auto size = pages * HugePageSize;
		r.at(address, size, dirtyPages * HugePageSize);
		ra.registerRegion(r);
		return address + size;
	}

	void checkBottomRegion(size_t pages, size_t dirtyPages) {
		Region rr;
		auto r = ra.regionsByRange.extractBestFit(&rr);
		assert(r !is null);
		assert(r.hugePageCount == pages);
		assert(r.dirtyPageCount == dirtyPages);
		ra.unusedRegions.insert(r);
	}

	void checkRegionsAndReset() {
		checkBottomRegion(5, 1);
		checkBottomRegion(3, 2);
		checkBottomRegion(4, 3);
		checkBottomRegion(2, 1);
		assert(ra.regionsByRange.empty);
		ra.regionsByClass.clear();
		ra.regionsByDirt.clear();
		ra.regionsByDirtAge.clear();
	}

	// Various clean and dirty regions:
	auto address = baseAddress;
	address = makeRegion(address, 3, 1);
	address = makeRegion(address, 2, 0);
	address = makeRegion(address, 3, 2);
	address = makeRegion(address, 2, 2);
	address = makeRegion(address, 1, 1);
	address = makeRegion(address, 1, 0);
	address = makeRegion(address, 1, 1);
	address = makeRegion(address, 1, 0);
	checkRegionsAndReset();

	// Same, interleaved:
	makeRegion(baseAddress, 3, 1);
	makeRegion(baseAddress + 5 * HugePageSize, 3, 2);
	makeRegion(baseAddress + 10 * HugePageSize, 1, 1);
	makeRegion(baseAddress + 12 * HugePageSize, 1, 1);
	makeRegion(baseAddress + 3 * HugePageSize, 2, 0);
	makeRegion(baseAddress + 8 * HugePageSize, 2, 2);
	makeRegion(baseAddress + 11 * HugePageSize, 1, 0);
	makeRegion(baseAddress + 13 * HugePageSize, 1, 0);
	checkRegionsAndReset();

	makeRegion(baseAddress + 10 * HugePageSize, 1, 1);
	makeRegion(baseAddress + 8 * HugePageSize, 2, 2);
	makeRegion(baseAddress + 13 * HugePageSize, 1, 0);
	makeRegion(baseAddress, 3, 1);
	makeRegion(baseAddress + 5 * HugePageSize, 3, 2);
	makeRegion(baseAddress + 11 * HugePageSize, 1, 0);
	makeRegion(baseAddress + 3 * HugePageSize, 2, 0);
	makeRegion(baseAddress + 12 * HugePageSize, 1, 1);
	checkRegionsAndReset();
}

ptrdiff_t classDirtAddrRegionCmp(Region* lhs, Region* rhs) {
	static assert(LgAddressSpace <= 48, "Address space too large!");

	auto l = ulong(lhs.allocClass) << 56;
	auto r = ulong(rhs.allocClass) << 56;

	// Descending order
	r |= (ulong(lhs.dirtClass) << 48);
	l |= (ulong(rhs.dirtClass) << 48);

	l |= cast(size_t) lhs.address;
	r |= cast(size_t) rhs.address;

	return (l > r) - (l < r);
}

ptrdiff_t dirtClassAddrRegionCmp(Region* lhs, Region* rhs) {
	static assert(LgAddressSpace <= 48, "Address space too large!");

	// Descending order
	auto r = ulong(lhs.dirtClass) << 56;
	auto l = ulong(rhs.dirtClass) << 56;

	// Descending order
	r |= (ulong(lhs.allocClass) << 48);
	l |= (ulong(rhs.allocClass) << 48);

	l |= cast(size_t) lhs.address;
	r |= cast(size_t) rhs.address;

	return (l > r) - (l < r);
}

ptrdiff_t dirtAgeAddrRegionCmp(Region* lhs, Region* rhs) {
	auto dirtEpochCmp =
		(lhs.dirtEpoch > rhs.dirtEpoch) - (lhs.dirtEpoch < rhs.dirtEpoch);
	if (dirtEpochCmp != 0) {
		return dirtEpochCmp;
	}

	// Descending order
	auto r = cast(size_t) lhs;
	auto l = cast(size_t) rhs;

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

unittest preferLongestDirtyRun {
	shared Base base;
	scope(exit) base.clear();

	shared RegionAllocator regionAllocator;
	regionAllocator.base = &base;

	HugePageDescriptor[32] hpdArray;
	void*[32] hpdAddresses;

	foreach (i; 0 .. 32) {
		assert(regionAllocator.acquire(&hpdArray[i]));
		hpdAddresses[i] = hpdArray[i].address;
	}

	void makeDirtyRun(HugePageDescriptor[] slice) {
		auto oldDirties = regionAllocator.dirtyPageCount;
		foreach (hpd; slice) {
			regionAllocator.release(&hpd);
		}

		assert(regionAllocator.dirtyPageCount == oldDirties + slice.length);
	}

	assert(regionAllocator.dirtyPageCount == 0);
	makeDirtyRun(hpdArray[3 .. 6]);
	makeDirtyRun(hpdArray[10 .. 16]);
	makeDirtyRun(hpdArray[20 .. 25]);
	assert(regionAllocator.dirtyPageCount == 14);

	// We allocate from the longest dirty run whenever possible:
	HugePageDescriptor hpd0;
	assert(regionAllocator.acquire(&hpd0));
	assert(hpd0.address is hpdAddresses[10]);

	HugePageDescriptor hpd1;
	assert(regionAllocator.acquire(&hpd1));
	assert(hpd1.address is hpdAddresses[11]);

	HugePageDescriptor hpd2;
	assert(regionAllocator.acquire(&hpd2));
	assert(hpd2.address is hpdAddresses[20]);

	HugePageDescriptor hpd3;
	assert(regionAllocator.acquire(&hpd3));
	assert(hpd3.address is hpdAddresses[12]);

	HugePageDescriptor hpd4;
	assert(regionAllocator.acquire(&hpd4));
	assert(hpd4.address is hpdAddresses[21]);
}
