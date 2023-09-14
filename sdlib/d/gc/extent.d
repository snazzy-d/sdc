module d.gc.extent;

import d.gc.base;
import d.gc.heap;
import d.gc.rbtree;
import d.gc.sizeclass;
import d.gc.spec;
import d.gc.util;

alias ExtentTree = RBTree!(Extent, addrRangeExtentCmp);

alias PHNode = heap.Node!Extent;
alias RBNode = rbtree.Node!Extent;

struct ExtentClass {
	ubyte data;

	this(ubyte data) {
		this.data = data;
	}

	enum Mask = (1 << 6) - 1;

	import d.gc.sizeclass;
	static assert((ClassCount.Small & ~Mask) == 0,
	              "ExtentClass doesn't fit on 6 bits!");

	static large() {
		return ExtentClass(0);
	}

	static slab(ubyte sizeClass) {
		// FIXME: in contract.
		assert(sizeClass < ClassCount.Small, "Invalid size class!");

		sizeClass += 1;
		return ExtentClass(sizeClass);
	}

	bool isSlab() const {
		return data != 0;
	}

	@property
	ubyte sizeClass() const {
		// FIXME: in contract.
		assert(isSlab(), "Non slab do not have a size class!");
		return (data - 1) & ubyte.max;
	}
}

unittest ExtentClass {
	auto l = ExtentClass.large();
	assert(!l.isSlab());

	auto s0 = ExtentClass.slab(0);
	assert(s0.isSlab());
	assert(s0.sizeClass == 0);

	auto s9 = ExtentClass.slab(9);
	assert(s9.isSlab());
	assert(s9.sizeClass == 9);

	auto smax = ExtentClass.slab(ClassCount.Small - 1);
	assert(smax.isSlab());
	assert(smax.sizeClass == ClassCount.Small - 1);
}

struct Extent {
private:
	/**
	 * This is a bitfield containing the following elements:
	 *  - e: The extent class.
	 *  - a: The arena index.
	 *  - n: The number of free slots.
	 * 
	 * 63    56 55    48 47    40 39    32 31    24 23    16 15     8 7      0
	 * nnnnnnnn nnnnnnnn ....aaaa aaaaaaaa ........ ........ ........ ..eeeeee
	 */
	ulong bits;

public:
	void* address;
	size_t sizeAndGen;

	import d.gc.hpd;
	HugePageDescriptor* hpd;

private:
	// TODO: Reuse this data to do something useful,
	// like garbage collection :P
	void* _pad;

	union Links {
		PHNode phnode;
		RBNode rbnode;
	}

	Links _links;

	import d.gc.bitmap;

	struct FreeSpaceData {
		ubyte[32] pad;
		shared Bitmap!256 freeSpaceFlags;
	}

	union Bitmaps {
		Bitmap!512 slabData;
		FreeSpaceData freeSpaceData;
	}

	union MetaData {
		// Slab occupancy (and metadata flags for supported size classes)
		Bitmaps slabData;

		// Metadata for large extents.
		size_t usedCapacity;
	}

	MetaData _metadata;

	this(uint arenaIndex, void* ptr, size_t size, ubyte generation,
	     HugePageDescriptor* hpd, ExtentClass ec) {
		// FIXME: in contract.
		assert((arenaIndex & ~ArenaMask) == 0, "Invalid arena index!");
		assert(isAligned(ptr, PageSize), "Invalid alignment!");
		assert(isAligned(size, PageSize), "Invalid size!");

		this.address = ptr;
		this.sizeAndGen = size | generation;
		this.hpd = hpd;

		bits = ec.data;
		bits |= ulong(arenaIndex) << 32;

		if (ec.isSlab()) {
			import d.gc.slab;
			bits |= ulong(binInfos[ec.sizeClass].slots) << 48;

			slabData.clear();
		} else {
			setUsedCapacity(size);
		}
	}

public:
	Extent* at(void* ptr, size_t size, HugePageDescriptor* hpd,
	           ExtentClass ec) {
		this = Extent(arenaIndex, ptr, size, generation, hpd, ec);
		return &this;
	}

	Extent* at(void* ptr, size_t size, HugePageDescriptor* hpd) {
		return at(ptr, size, hpd, ExtentClass.large());
	}

	static fromSlot(uint arenaIndex, Base.Slot slot) {
		// FIXME: in contract
		assert((arenaIndex & ~ArenaMask) == 0, "Invalid arena index!");
		assert(slot.address !is null, "Slot is empty!");
		assert(isAligned(slot.address, ExtentAlign),
		       "Invalid slot alignement!");

		auto e = cast(Extent*) slot.address;
		e.bits = ulong(arenaIndex) << 32;
		e.sizeAndGen = slot.generation;

		return e;
	}

	@property
	size_t size() const {
		return sizeAndGen & ~PageMask;
	}

	@property
	uint pageCount() const {
		auto pc = sizeAndGen / PageSize;

		assert(pc == pc & uint.max, "Invalid page count!");
		return pc & uint.max;
	}

	bool isHuge() const {
		return size > HugePageSize;
	}

	@property
	uint hpdIndex() const {
		assert(isHuge() || hpd.address is alignDown(address, HugePageSize));
		assert(!isHuge() || isAligned(address, HugePageSize));

		return ((cast(size_t) address) / PageSize) % PagesInHugePage;
	}

	@property
	ubyte generation() const {
		return sizeAndGen & 0xff;
	}

	@property
	ref PHNode phnode() {
		return _links.phnode;
	}

	@property
	ref RBNode rbnode() {
		return _links.rbnode;
	}

	bool contains(void* ptr) const {
		return ptr >= address && ptr < address + size;
	}

	/**
	 * Arena.
	 */
	@property
	uint arenaIndex() const {
		return (bits >> 32) & ArenaMask;
	}

	@property
	bool containsPointers() const {
		return (arenaIndex & 0x01) != 0;
	}

	/**
	 * Slab features.
	 */
	@property
	auto extentClass() const {
		return ExtentClass(bits & ExtentClass.Mask);
	}

	bool isSlab() const {
		auto ec = extentClass;
		return ec.isSlab();
	}

	@property
	ubyte sizeClass() const {
		auto ec = extentClass;
		return ec.sizeClass;
	}

	@property
	size_t slotSize() const {
		assert(isSlab(), "slotSize accessed on non slab!");

		import d.gc.slab;
		return binInfos[sizeClass].itemSize;
	}

	@property
	uint slotCount() const {
		assert(isSlab(), "slotCount accessed on non slab!");

		import d.gc.slab;
		return binInfos[sizeClass].slots;
	}

	@property
	uint freeSlots() const {
		// FIXME: in contract.
		assert(isSlab(), "freeSlots accessed on non slab!");

		enum Mask = (1 << 10) - 1;
		return (bits >> 48) & Mask;
	}

	uint allocate() {
		// FIXME: in contract.
		assert(isSlab(), "allocate accessed on non slab!");
		assert(freeSlots > 0, "Slab is full!");

		scope(success) bits -= (1UL << 48);
		return slabData.setFirst();
	}

	void free(uint index) {
		// FIXME: in contract.
		assert(isSlab(), "free accessed on non slab!");
		assert(slabData.valueAt(index), "Slot is already free!");

		bits += (1UL << 48);
		slabData.clearBit(index);
	}

	@property
	ref Bitmap!512 slabData() {
		// FIXME: in contract.
		assert(isSlab(), "slabData accessed on non slab!");

		return _metadata.slabData.slabData;
	}

	/**
	 * Freespace Flag features for slabs.
	 */

	@property
	bool supportsFreeSpace() const {
		return isAppendableSizeClass(sizeClass);
	}

	@property
	ref shared(Bitmap!256) freeSpaceFlags() {
		assert(isSlab(), "freeSpaceFlags accessed on non slab!");
		assert(supportsFreeSpace, "freeSpaceFlags not supported!");

		return _metadata.slabData.freeSpaceData.freeSpaceFlags;
	}

	bool setFreeSpace(uint index, size_t freeSpace) {
		assert(isSlab(), "setFreeSpace accessed on non slab!");
		assert(freeSpace <= slotSize, "freeSpace exceeds alloc size!");
		assert(index < slotCount, "index is out of range!");
		assert(supportsFreeSpace, "size class not supports freeSpace!");

		if (freeSpace == 0) {
			freeSpaceFlags.clearBitAtomic(index);
			return true;
		}

		// Encode freespace and write it to the last byte (or two bytes) of alloc.
		writePackedFreeSpace(cast(ushort*) (address + slotSize - 2),
		                     freeSpace & ushort.max);
		freeSpaceFlags.setBitAtomic(index);

		return true;
	}

	size_t getFreeSpace(uint index) {
		assert(isSlab(), "getFreeSpace accessed on non slab!");
		assert(index < slotCount, "index is out of range!");

		if (!supportsFreeSpace || !freeSpaceFlags.valueAtAtomic(index)) {
			return 0;
		}

		// Decode freespace, found in the final byte (or two bytes) of the alloc:
		return readPackedFreeSpace(cast(ushort*) (address + slotSize - 2));
	}

	/**
	 * Large features.
	 */
	bool isLarge() const {
		return !isSlab();
	}

	@property
	ulong usedCapacity() {
		assert(isLarge(), "usedCapacity accessed on non large!");
		return _metadata.usedCapacity;
	}

	void setUsedCapacity(size_t size) {
		assert(isLarge(), "Cannot set used capacity on a slab alloc!");
		_metadata.usedCapacity = size;
	}
}

static assert(Extent.sizeof == ExtentSize, "Unexpected Extent size!");
static assert(Extent.sizeof == ExtentAlign, "Unexpected Extent alignment!");

ptrdiff_t addrExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs.address;
	auto r = cast(size_t) rhs.address;

	// We need to compare that way to avoid integer overflow.
	return (l > r) - (l < r);
}

ptrdiff_t addrRangeExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs.address;
	auto rstart = cast(size_t) rhs.address;
	auto rend = rstart + rhs.size;

	// We need to compare that way to avoid integer overflow.
	return (l >= rend) - (l < rstart);
}

ptrdiff_t unusedExtentCmp(Extent* lhs, Extent* rhs) {
	static assert(LgAddressSpace <= 56, "Address space too large!");

	auto l = ulong(lhs.generation) << 56;
	auto r = ulong(rhs.generation) << 56;

	l |= cast(size_t) lhs;
	r |= cast(size_t) rhs;

	return (l > r) - (l < r);
}

unittest contains {
	auto base = cast(void*) 0x56789abcd000;
	enum Size = 13 * PageSize;

	Extent e;
	e.address = base;
	e.sizeAndGen = Size;

	assert(!e.contains(base - 1));
	assert(!e.contains(base + Size));

	foreach (i; 0 .. Size) {
		assert(e.contains(base + i));
	}
}

unittest allocfree {
	Extent e;
	e.at(null, PageSize, null, ExtentClass.slab(0));

	assert(e.isSlab());
	assert(e.sizeClass == 0);
	assert(e.freeSlots == 512);

	assert(e.allocate() == 0);
	assert(e.freeSlots == 511);

	assert(e.allocate() == 1);
	assert(e.freeSlots == 510);

	assert(e.allocate() == 2);
	assert(e.freeSlots == 509);

	e.free(1);
	assert(e.freeSlots == 510);

	assert(e.allocate() == 1);
	assert(e.freeSlots == 509);

	assert(e.allocate() == 3);
	assert(e.freeSlots == 508);

	e.free(0);
	e.free(3);
	e.free(2);
	e.free(1);
	assert(e.freeSlots == 512);
}

/**
 * Packed Free Space is stored as a 15-bit unsigned integer, in one or two bytes:
 *
 * /---- byte at ptr ----\ /-- byte at ptr + 1 --\
 * B7 B6 B5 B4 B3 B2 B1 B0 A7 A6 A5 A4 A3 A2 A1 A0
 * \_________15 bits unsigned integer_________/  \_ Set if and only if B0..B7 used.
 */

ushort readPackedFreeSpace(ushort* ptr) {
	auto data = loadBigEndian(ptr);
	auto mask = 0x7f | -(data & 1);
	return (data >> 1) & mask;
}

void writePackedFreeSpace(ushort* ptr, ushort x) {
	assert(x < 0x8000, "x does not fit in 15 bits!");

	auto mask = 0x7f - x >> 8 | 0xff;
	auto base = x << 1 | mask >> 8 & 1;

	auto current = loadBigEndian(ptr);
	auto delta = (current ^ base) & mask;
	auto value = current ^ delta;

	storeBigEndian(ptr, cast(ushort) value);
}

unittest PackedFreeSpace {
	ubyte[2] a;
	foreach (ushort i; 0 .. 0x8000) {
		auto p = cast(ushort*) a.ptr;
		writePackedFreeSpace(p, i);
		assert(readPackedFreeSpace(p) == i);
	}

	foreach (x; 0 .. 256) {
		a[0] = 0xff & x;
		foreach (ubyte y; 0 .. 0x80) {
			auto p = cast(ushort*) a.ptr;
			writePackedFreeSpace(p, y);
			assert(readPackedFreeSpace(p) == y);
			assert(a[0] == x);
		}
	}
}
