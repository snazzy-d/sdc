module d.gc.slab;

import d.gc.emap;
import d.gc.extent;
import d.gc.spec;
import d.gc.util;

enum InvalidBinID = 0xff;

struct SlabAllocGeometry {
	const void* address;
	uint size;
	uint index;

	this(PageDescriptor pd, const void* ptr) {
		assert(pd.isSlab(), "Expected a slab!");

		import d.gc.util;
		auto offset = alignDownOffset(ptr, PageSize) + pd.index * PageSize;
		index = binInfos[pd.sizeClass].computeIndex(offset);

		auto base = ptr - offset;
		size = binInfos[pd.sizeClass].itemSize;
		address = base + index * size;
	}
}

struct SlabAllocInfo {
private:
	SlabAllocGeometry sg;
	Extent* e;
	bool allowsMetaData = false;
public:
	bool hasMetaData = false;

	this(PageDescriptor pd, const void* ptr) {
		assert(pd.isSlab(), "Expected a slab!");

		e = pd.extent;
		sg = SlabAllocGeometry(pd, ptr);
		allowsMetaData = sizeClassSupportsMetadata(pd.sizeClass);
		hasMetaData = allowsMetaData && e.hasMetaData(sg.index);
	}

	@property
	auto address() {
		return sg.address;
	}

	@property
	size_t slotCapacity() {
		return sg.size;
	}

	@property
	size_t usedCapacity() {
		return allowsMetaData ? sg.size - freeSpace : 0;
	}

	bool setUsedCapacity(size_t size) {
		if (!allowsMetaData || (size > slotCapacity)) {
			return false;
		}

		setFreeSpace(sg.size - size);
		return true;
	}

	@property
	size_t freeSpace() {
		return hasMetaData ? readPackedFreeSpace(freeSpacePtr) : 0;
	}

	void setFreeSpace(size_t size) {
		assert(allowsMetaData, "size class not supports slab metadata!");

		if (size == 0) {
			disableMetaData();
			return;
		}

		writePackedFreeSpace(freeSpacePtr, size & ushort.max);
		enableMetaData();
	}

private:

	void enableMetaData() {
		assert(allowsMetaData, "size class not supports slab metadata!");

		if (!hasMetaData) {
			e.enableMetaData(sg.index);
			hasMetaData = true;
		}
	}

	void disableMetaData() {
		assert(allowsMetaData, "size class not supports slab metadata!");

		if (hasMetaData) {
			e.disableMetaData(sg.index);
			hasMetaData = false;
		}
	}

	@property
	T* ptrToAllocEnd(T)() {
		return cast(T*) (sg.address + sg.size) - T.sizeof;
	}

	alias freeSpacePtr = ptrToAllocEnd!ushort;
}

/**
 * Packed Free Space is stored as a 14-bit unsigned integer, in one or two bytes:
 *
 * /---- byte at ptr ----\ /-- byte at ptr + 1 --\
 * B7 B6 B5 B4 B3 B2 B1 B0 A7 A6 A5 A4 A3 A2 A1 A0
 * \_______14 bits unsigned integer________/  \  \_ Set if and only if B0..B7 used.
 *                                             \_ Set when finalizer is present;
 *                                                preserved when writing.
 */

static assert(MaxSmallSize < 0x4000,
              "Max small alloc size doesn't fit in 14 bits!");

ushort readPackedFreeSpace(ushort* ptr) {
	auto data = loadBigEndian(ptr);
	auto mask = 0x3f | -(data & 1);
	return (data >> 2) & mask;
}

void writePackedFreeSpace(ushort* ptr, ushort x) {
	assert(x < 0x4000, "x does not fit in 14 bits!");

	bool isLarge = x > 0x3f;
	ushort native = (x << 2 | isLarge) & ushort.max;
	auto base = nativeToBigEndian(native);

	auto smallMask = nativeToBigEndian!ushort(ushort(0xfd));
	auto largeMask = nativeToBigEndian!ushort(ushort(0xfffd));
	auto mask = isLarge ? largeMask : smallMask;

	auto current = *ptr;
	auto delta = (current ^ base) & mask;
	auto value = current ^ delta;

	*ptr = value & ushort.max;
}

unittest packedFreeSpace {
	enum FinalizerBit = nativeToBigEndian!ushort(ushort(0x2));

	ubyte[2] a;
	auto p = cast(ushort*) a.ptr;

	foreach (ushort i; 0 .. 0x4000) {
		// With finalizer bit set:
		*p |= FinalizerBit;
		writePackedFreeSpace(p, i);
		assert(readPackedFreeSpace(p) == i);
		assert(*p & FinalizerBit);

		// With finalizer bit cleared:
		*p &= ~FinalizerBit;
		// Should remain same as before:
		assert(readPackedFreeSpace(p) == i);
		writePackedFreeSpace(p, i);
		assert(!(*p & FinalizerBit));
	}

	// Make sure we do not distrub the penultimate byte
	// when the value is small enough.
	foreach (x; 0 .. 256) {
		a[0] = 0xff & x;
		foreach (ubyte y; 0 .. 0x40) {
			writePackedFreeSpace(p, y);
			assert(readPackedFreeSpace(p) == y);
			assert(a[0] == x);
		}
	}
}

struct BinInfo {
	ushort itemSize;
	ushort slots;
	ubyte needPages;
	ubyte shift;
	ushort mul;

	this(ushort itemSize, ubyte shift, ubyte needPages, ushort slots) {
		this.itemSize = itemSize;
		this.slots = slots;
		this.needPages = needPages;
		this.shift = (shift + 17) & 0xff;

		// XXX: out contract
		enum MaxShiftMask = (8 * size_t.sizeof) - 1;
		assert(this.shift == (this.shift & MaxShiftMask));

		/**
		 * This is a bunch of magic values used to avoid requiring
		 * division to find the index of an item within a run.
		 *
		 * Computed using finddivisor.d
		 */
		ushort[4] mulIndices = [32768, 26215, 21846, 18725];
		auto tag = (itemSize >> shift) & 0x03;
		this.mul = mulIndices[tag];
	}

	uint computeIndex(size_t offset) const {
		// FIXME: in contract.
		assert(offset < needPages * PageSize, "Offset out of bounds!");

		return cast(uint) ((offset * mul) >> shift);
	}
}

import d.gc.sizeclass;
immutable BinInfo[ClassCount.Small] binInfos = getBinInfos();
