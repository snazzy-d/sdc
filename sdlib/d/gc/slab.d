module d.gc.slab;

import d.gc.emap;
import d.gc.extent;
import d.gc.size;
import d.gc.spec;
import d.gc.util;

enum InvalidBinID = 0xff;

struct SlabEntry {
private:
	/**
	 * This is a bitfield containing the following elements:
	 *  - i: The index of the item within the slab.
	 *  - a: The address of the slab.
	 *  - s: The size class of the slab.
	 * 
	 * 63    56 55    48 47    40 39    32 31    24 23    16 15     8 7      0
	 * .......i iiiiiiii aaaaaaaa aaaaaaaa aaaaaaaa aaaaaaaa aaaa.... ..ssssss
	 */
	ulong bits;

	// Verify our assumptions.
	static assert(LgAddressSpace <= 48, "Address space too large!");
	static assert(LgPageSize >= 8, "Not enough space in low bits!");

	// Useful constants for bit manipulations.
	enum IndexShift = 48;

public:
	this(PageDescriptor pd, const void* ptr) {
		assert(pd.isSlab(), "Expected a slab!");

		auto ec = pd.extentClass;
		auto sc = ec.sizeClass;

		auto offset = pd.computeOffset(ptr);
		auto index = binInfos[sc].computeIndex(offset);
		auto base = ptr - offset;

		bits = sc;
		bits |= ulong(index) << IndexShift;
		bits |= (cast(ulong) base) & PagePointerMask;
	}

	@property
	uint index() const {
		return bits >> IndexShift;
	}

	@property
	void* base() const {
		return cast(void*) (bits & PagePointerMask);
	}

	@property
	ubyte sizeClass() const {
		return bits & 0xff;
	}

	void* computeAddress() const {
		auto size = binInfos[sizeClass].slotSize;
		return base + index * size;
	}

	const(void*)[] computeRange() const {
		auto size = binInfos[sizeClass].slotSize;
		auto address = cast(void**) (base + index * size);

		return address[0 .. size / PointerSize];
	}
}

unittest SlabRange {
	auto pd = PageDescriptor(0x100000000000000a);

	assert(pd.extent is null);
	assert(pd.index == 1);

	auto ec = pd.extentClass;
	assert(ec.sizeClass == 9);

	auto ptr = cast(void*) 0x56789abcd123;
	auto base = cast(void*) 0x56789abcc000;
	auto slot = cast(void*) 0x56789abcd0e0;

	auto se = SlabEntry(pd, ptr);
	assert(se.index == 45);
	assert(se.base is base);
	assert(se.sizeClass == 9);

	auto addr = se.computeAddress();
	assert(addr is slot);

	auto r0 = se.computeRange();
	assert(r0.ptr is cast(const(void*)*) slot);
	assert(r0.length == 12);
}

struct SlotMetadata {
private:
	struct FreeSpaceData {
		ushort[size_t.sizeof / ushort.sizeof - 1] _pad;
		ushort freeSpace;
	}

	union Data {
		size_t finalizerData;
		FreeSpaceData freeSpaceData;
	}

	Data data;

	enum FinalizerBit = nativeToBigEndian!size_t(0x2);

public:
	static SlotMetadata* fromBlock(void* ptr, size_t slotSize) {
		return cast(SlotMetadata*) (ptr + slotSize) - 1;
	}

	@property
	ushort freeSpace() {
		return readPackedFreeSpace(&data.freeSpaceData.freeSpace);
	}

	void setFreeSpace(size_t size) {
		assert(size > 0, "Attempt to set a slot metadata size of 0!");

		writePackedFreeSpace(&data.freeSpaceData.freeSpace, size);
	}

	@property
	Finalizer finalizer() {
		return hasFinalizer
			? cast(Finalizer) (data.finalizerData & AddressMask)
			: null;
	}

	@property
	bool hasFinalizer() {
		return (data.finalizerData & FinalizerBit) != 0;
	}
}

static assert(SlotMetadata.sizeof == size_t.sizeof,
              "SlotMetadata must fit in size_t!");

struct SlabAllocInfo {
private:
	Extent* e;

	uint index;
	uint slotSize;
	const void* _address;

	bool supportsMetadata = false;
	bool _hasMetadata = false;

public:
	this(PageDescriptor pd, const void* ptr) {
		assert(pd.isSlab(), "Expected a slab!");

		e = pd.extent;

		auto se = SlabEntry(pd, ptr);
		index = se.index;
		slotSize = binInfos[se.sizeClass].slotSize;
		_address = se.base + index * slotSize;

		auto ec = pd.extentClass;
		supportsMetadata = ec.supportsMetadata;
		_hasMetadata = ec.supportsMetadata && e.hasMetadata(index);
	}

	@property
	auto hasMetadata() {
		return _hasMetadata;
	}

	@property
	auto address() {
		return _address;
	}

	@property
	size_t slotCapacity() {
		return slotSize - (finalizerEnabled ? PointerSize : 0);
	}

	@property
	size_t usedCapacity() {
		return slotSize - freeSpace;
	}

	bool setUsedCapacity(size_t size) {
		if (!supportsMetadata || size > slotCapacity) {
			return false;
		}

		setFreeSpace(slotSize - size);
		return true;
	}

	@property
	Finalizer finalizer() {
		return _hasMetadata ? slotMetadata.finalizer : null;
	}

	void initializeMetadata(Finalizer initialFinalizer,
	                        size_t initialUsedCapacity) {
		assert(isLittleEndian(), "Currently does not work on big-endian!");
		assert(supportsMetadata, "size class not supports slab metadata!");

		bool hasFinalizer = initialFinalizer !is null;
		assert(
			initialUsedCapacity <= slotSize - (hasFinalizer ? PointerSize : 0),
			"Insufficient alloc capacity!"
		);

		auto finalizerValue = cast(size_t) cast(void*) initialFinalizer;
		assert((finalizerValue & AddressMask) == finalizerValue,
		       "New finalizer pointer is invalid!");

		auto freeSpaceValue = slotSize - initialUsedCapacity;
		bool isLarge = freeSpaceValue > 0x3f;
		auto finalizerSet = hasFinalizer << 1;
		ushort native =
			(freeSpaceValue << 2 | isLarge | finalizerSet) & ushort.max;

		auto newMetadata = nativeToBigEndian!size_t(native);

		// TODO: Currently only works on little-endian!!!
		// On a big-endian machine, the unused high 16 bits of a pointer will be
		// found at the start, rather than end, of the memory that it occupies,
		// and the freespace (newMetadata) will collide with the finalizer.
		slotMetadata.data.finalizerData = newMetadata | finalizerValue;
		e.enableMetadata(index);
		_hasMetadata = true;
	}

private:
	@property
	SlotMetadata* slotMetadata() {
		return SlotMetadata.fromBlock(cast(void*) address, slotSize);
	}

	@property
	size_t freeSpace() {
		return _hasMetadata ? slotMetadata.freeSpace : 0;
	}

	void setFreeSpace(size_t size) {
		assert(supportsMetadata, "size class not supports slab metadata!");
		assert(size <= slotSize, "size exceeds slot size!");

		if (size == 0) {
			if (_hasMetadata) {
				e.disableMetadata(index);
				_hasMetadata = false;
			}

			return;
		}

		slotMetadata.setFreeSpace(size);
		if (!_hasMetadata) {
			e.enableMetadata(index);
			_hasMetadata = true;
		}
	}

	@property
	bool finalizerEnabled() {
		// Right now we fetch hasMetadata eagerly, but the FinalizerBit check
		// is cheaper. But it may be worthwhile to return early if FinalizerBit
		// is clear, i.e. to snoop the extent's metadata lazily. The reasons:
		// 1) If the slot is not full, the bit at the FinalizerBit position
		//    is most likely 0.
		// 2) If it has metadata, usually it won't have a finalizer: still 0.
		// 3) If the metadata space contains an aligned pointer, the last byte
		//    will be the MSB of that pointer, which will always be 0.
		// 4) If the space contains a number, its MSB will likely be zero,
		//    as most numbers are small.
		// 5) If there is something else in there, that is not heavily biased
		//    (float, random/compressed data) then we're still at 50/50.
		// We should expect to find a zero in there the VAST majority of the time.

		return _hasMetadata && slotMetadata.hasFinalizer;
	}
}

unittest SlabAllocInfo {
	import d.gc.base;
	shared Base base;
	scope(exit) base.clear();

	auto slot = base.allocSlot();
	auto e = Extent.fromSlot(0, slot);
	auto block = base.reserveAddressSpace(BlockSize);
	assert(block !is null);

	static SlabAllocInfo simulateSmallAlloc(size_t size, uint slotIndex) {
		auto ec = ExtentClass.slab(getSizeClass(size));
		e.at(block, 1, null, ec);

		void*[512] buffer = void;
		e.batchAllocate(buffer.ptr, 512, size);

		auto pd = PageDescriptor(e, ec);
		auto allocAddress = block + slotIndex * size;
		return SlabAllocInfo(pd, allocAddress);
	}

	// When metadata is not supported by the size class.
	foreach (size; [1, 6, 8]) {
		auto sc = getSizeClass(size);
		assert(!sizeClassSupportsMetadata(sc));
		assert(!binInfos[sc].supportsMetadata);

		foreach (slotIndex; 0 .. binInfos[sc].nslots + 1) {
			auto si = simulateSmallAlloc(size, slotIndex);
			assert(si.slotCapacity == getAllocSize(size));
			assert(!si.supportsMetadata);
			assert(!si.hasMetadata);
			assert(si.freeSpace == 0);
			assert(!si.setUsedCapacity(0));
			assert(!si.setUsedCapacity(1));
		}
	}

	// Finalizers.
	static void destruct_a(void* ptr, size_t size) {}
	static void destruct_b(void* ptr, size_t size) {}

	// When metadata is supported by the size class (not exhaustive).
	foreach (size;
		[15, 16, 300, 320, 1000, 1024, MaxSmallSize - 1, MaxSmallSize]
	) {
		auto sc = getSizeClass(size);
		assert(sizeClassSupportsMetadata(sc));
		assert(binInfos[sc].supportsMetadata);

		foreach (slotIndex; 0 .. binInfos[sc].nslots + 1) {
			auto si = simulateSmallAlloc(size, slotIndex);
			assert(si.supportsMetadata);
			auto slotCapacity = si.slotCapacity;
			assert(slotCapacity == getAllocSize(size));
			si.setUsedCapacity(size);
			assert(si.usedCapacity == size);
			assert(si.hasMetadata == (size != slotCapacity));
			assert(si.freeSpace == slotCapacity - size);
			assert(!si.setUsedCapacity(slotCapacity + 1));

			foreach (size_t i; 0 .. slotCapacity + 1) {
				assert(si.setUsedCapacity(i));
				assert(si.usedCapacity == i);
				assert(si.hasMetadata == (i < slotCapacity));
				assert(si.freeSpace == si.slotCapacity - i);
				si.setFreeSpace(i);
				assert(si.freeSpace == i);
				assert(si.hasMetadata == (i > 0));
				assert(si.usedCapacity == si.slotCapacity - i);
			}

			// Test finalizers:
			auto regularSlotCapacity = si.slotCapacity;
			auto finalizedSlotCapacity = regularSlotCapacity - PointerSize;

			foreach (size_t i; 0 .. finalizedSlotCapacity + 1) {
				// Without finalizer:
				si.initializeMetadata(null, i);
				assert(si.usedCapacity == i);
				assert(si.slotCapacity == regularSlotCapacity);
				assert(cast(void*) si.finalizer == null);
				// With finalizer:
				si.initializeMetadata(&destruct_a, i);
				assert(si.usedCapacity == i);
				assert(si.slotCapacity == finalizedSlotCapacity);
				assert(cast(void*) si.finalizer == cast(void*) &destruct_a);
				si.initializeMetadata(&destruct_b, i);
				assert(si.usedCapacity == i);
				assert(si.slotCapacity == finalizedSlotCapacity);
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

void writePackedFreeSpace(ushort* ptr, size_t x) {
	assert(x < 0x4000, "x does not fit in 14 bits!");

	bool isLarge = x > 0x3f;
	ushort native = (x << 2 | isLarge) & ushort.max;
	auto base = nativeToBigEndian(native);

	auto smallMask = nativeToBigEndian!ushort(0xfd);
	auto largeMask = nativeToBigEndian!ushort(0xfffd);
	auto mask = isLarge ? largeMask : smallMask;

	auto current = *ptr;
	auto delta = (current ^ base) & mask;
	auto value = current ^ delta;

	*ptr = value & ushort.max;
}

unittest packedFreeSpace {
	enum FinalizerBit = nativeToBigEndian!ushort(0x2);

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
	ushort slotSize;
	ushort nslots;
	ubyte npages;
	ubyte shift;
	ushort mul;

	this(ushort slotSize, ubyte shift, ubyte npages, ushort nslots) {
		this.slotSize = slotSize;
		this.nslots = nslots;
		this.npages = npages;
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
		auto tag = (slotSize >> shift) & 0x03;
		this.mul = mulIndices[tag];
	}

	uint computeIndex(size_t offset) const {
		// FIXME: in contract.
		assert(offset < npages * PageSize, "Offset out of bounds!");

		return cast(uint) ((offset * mul) >> shift);
	}

	@property
	bool dense() const {
		// We use the number of items as a proxy to estimate the density
		// of the span. Dense spans are assumed to be long lived.
		return nslots > 16;
	}

	@property
	bool sparse() const {
		return !dense;
	}

	@property
	bool supportsMetadata() const {
		return nslots <= 256;
	}

	@property
	bool supportsInlineMarking() const {
		return nslots <= 128;
	}
}

import d.gc.sizeclass;
immutable BinInfo[BinCount] binInfos = getBinInfos();

unittest binInfos {
	foreach (uint sc, bin; binInfos) {
		assert(bin.supportsMetadata == sizeClassSupportsMetadata(sc));
		assert(bin.supportsInlineMarking == sizeClassSupportsInlineMarking(sc));
		assert(bin.dense == isDenseSizeClass(sc));
		assert(bin.sparse == isSparseSizeClass(sc));
	}
}
