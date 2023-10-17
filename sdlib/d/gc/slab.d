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
	bool _allowsMetaData = false;
	bool _hasMetaData = false;

public:
	this(PageDescriptor pd, const void* ptr) {
		assert(pd.isSlab(), "Expected a slab!");

		e = pd.extent;
		sg = SlabAllocGeometry(pd, ptr);
		_allowsMetaData = sizeClassSupportsMetadata(pd.sizeClass);
		_hasMetaData = _allowsMetaData && e.hasMetaData(sg.index);
	}

	@property
	auto allowsMetaData() {
		return _allowsMetaData;
	}

	@property
	auto hasMetaData() {
		return _hasMetaData;
	}

	@property
	auto address() {
		return sg.address;
	}

	@property
	size_t slotCapacity() {
		return sg.size - (finalizerEnabled ? PointerSize : 0);
	}

	@property
	size_t usedCapacity() {
		return sg.size - freeSpace;
	}

	bool setUsedCapacity(size_t size) {
		if (!_allowsMetaData || (size > slotCapacity)) {
			return false;
		}

		setFreeSpace(sg.size - size);
		return true;
	}

	@property
	Finalizer finalizer() {
		if (!finalizerEnabled) {
			return null;
		}

		return cast(Finalizer) cast(void*) (*finalizerPtr & AddressMask);
	}

	void setFinalizer(Finalizer newFinalizer) {
		assert(hasMetaData,
		       "Metadata is not present! (must set used capacity first)");

		if (newFinalizer is null) {
			*finalizerPtr &= ~FinalizerBit;
			return;
		}

		auto _newFinalizer = cast(size_t) cast(void*) newFinalizer;
		assert((_newFinalizer & AddressMask) == _newFinalizer,
		       "New finalizer pointer is invalid!");

		auto newMetaData = (*finalizerPtr & ~AddressMask) | FinalizerBit;
		*finalizerPtr = newMetaData | _newFinalizer;
	}

private:
	@property
	size_t freeSpace() {
		return _hasMetaData ? readPackedFreeSpace(freeSpacePtr) : 0;
	}

	void setFreeSpace(size_t size) {
		assert(_allowsMetaData, "size class not supports slab metadata!");
		assert(size <= sg.size, "size exceeds alloc size!");

		if (size == 0) {
			disableMetaData();
			return;
		}

		writePackedFreeSpace(freeSpacePtr, size & ushort.max);
		enableMetaData();
	}

	void enableMetaData() {
		assert(_allowsMetaData, "size class not supports slab metadata!");

		if (!_hasMetaData) {
			e.enableMetaData(sg.index);
			_hasMetaData = true;
		}
	}

	void disableMetaData() {
		assert(_allowsMetaData, "size class not supports slab metadata!");

		if (_hasMetaData) {
			e.disableMetaData(sg.index);
			_hasMetaData = false;
		}
	}

	enum FinalizerBit = nativeToBigEndian!size_t(0x2);

	@property
	bool finalizerEnabled() {
		return hasMetaData && (*finalizerPtr & FinalizerBit);
	}

	@property
	T* ptrToAllocEnd(T)() {
		return cast(T*) (sg.address + sg.size - T.sizeof);
	}

	alias freeSpacePtr = ptrToAllocEnd!ushort;
	alias finalizerPtr = ptrToAllocEnd!size_t;
}

unittest SlabAllocInfo {
	import d.gc.base;
	static Base base;
	scope(exit) base.clear();

	auto slot = base.allocSlot();
	auto e = Extent.fromSlot(0, slot);
	auto block = base.reserveAddressSpace(HugePageSize);
	assert(block !is null);

	static SlabAllocInfo simulateSmallAlloc(size_t size, uint slotIndex) {
		auto ec = ExtentClass.slab(getSizeClass(size));
		e.at(block, PageSize, null, ec);
		auto allocAddress = block;
		// TODO: it is probably possible to make this less hideous:
		foreach (s; 0 .. slotIndex) {
			assert(e.allocate() == s);
			allocAddress += size;
		}

		auto pd = PageDescriptor(e, ec);
		return SlabAllocInfo(pd, allocAddress);
	}

	// When metadata is not supported by the size class:
	foreach (size; [1, 6, 8, 20, 24, 35, 40, 50, 56]) {
		auto sc = getSizeClass(size);
		foreach (slotIndex; 0 .. binInfos[sc].slots + 1) {
			auto si = simulateSmallAlloc(size, slotIndex);
			assert(si.slotCapacity == getAllocSize(size));
			assert(!si.allowsMetaData);
			assert(!si.hasMetaData);
			assert(si.freeSpace == 0);
			assert(!si.setUsedCapacity(0));
			assert(!si.setUsedCapacity(1));
		}
	}

	// Finalizers
	static void destruct_a(void* ptr, size_t size) {}
	static void destruct_b(void* ptr, size_t size) {}

	// When metadata is supported by the size class (not exhaustive) :
	foreach (size;
		[15, 16, 300, 320, 1000, 1024, MaxSmallSize - 1, MaxSmallSize]
	) {
		auto sc = getSizeClass(size);
		foreach (slotIndex; 0 .. binInfos[sc].slots + 1) {
			auto si = simulateSmallAlloc(size, slotIndex);
			assert(si.allowsMetaData);
			auto slotCapacity = si.slotCapacity;
			assert(slotCapacity == getAllocSize(size));
			si.setUsedCapacity(size);
			assert(si.usedCapacity == size);
			assert(si.hasMetaData == (size != slotCapacity));
			assert(si.freeSpace == slotCapacity - size);
			assert(!si.setUsedCapacity(slotCapacity + 1));

			foreach (size_t i; 0 .. slotCapacity + 1) {
				assert(si.setUsedCapacity(i));
				assert(si.usedCapacity == i);
				assert(si.hasMetaData == (i < slotCapacity));
				assert(si.freeSpace == si.slotCapacity - i);
				si.setFreeSpace(i);
				assert(si.freeSpace == i);
				assert(si.hasMetaData == (i > 0));
				assert(si.usedCapacity == si.slotCapacity - i);
			}

			// Set a finalizer:
			auto prevSlotCapacity = si.slotCapacity;
			si.setFinalizer(&destruct_a);
			assert(si.slotCapacity == prevSlotCapacity - PointerSize);

			foreach (size_t i; 0 .. si.slotCapacity + 1) {
				si.setFinalizer(&destruct_a);
				// Confirm that setting capacity does not clobber finalizer:
				assert(si.setUsedCapacity(i));
				assert(cast(void*) si.finalizer == cast(void*) &destruct_a);
				// Confirm that disabling finalizer does not clobber capacity:
				prevSlotCapacity = si.slotCapacity;
				si.setFinalizer(null);
				assert(cast(void*) si.finalizer == null);
				assert(si.usedCapacity == i);
				// ... and restores max slot capacity to the full alloc size:
				assert(si.slotCapacity == prevSlotCapacity + PointerSize);
				// Confirm that setting finalizer does not clobber capacity:
				si.setFinalizer(&destruct_b);
				assert(si.usedCapacity == i);
				assert(cast(void*) si.finalizer == cast(void*) &destruct_b);
			}
		}
	}
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
