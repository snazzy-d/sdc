module d.gc.emap;

import d.gc.extent;
import d.gc.spec;
import d.gc.util;

@property
shared(ExtentMap)* gExtentMap() {
	static shared ExtentMap emap;

	if (emap.tree.base is null) {
		import d.gc.base;
		emap.tree.base = &gBase;
	}

	return &emap;
}

struct ExtentMap {
private:
	import d.gc.rtree;
	RTree!PageDescriptor tree;

public:
	PageDescriptor lookup(void* address) shared {
		auto leaf = tree.get(address);
		return leaf is null ? PageDescriptor(0) : leaf.load();
	}

	bool remap(Extent* extent, ExtentClass ec) shared {
		return tree
			.setRange(extent.address, extent.size, PageDescriptor(extent, ec));
	}

	bool remap(Extent* extent) shared {
		// FIXME: in contract.
		assert(!extent.isSlab(), "Extent is a slab!");
		return remap(extent, ExtentClass.large());
	}

	void clear(Extent* extent) shared {
		tree.clearRange(extent.address, extent.size);
	}
}

struct PageDescriptor {
private:
	/**
	 * The extent itself is 7 bits aligned and the address space 48 bits.
	 * This leaves us with the low 7 bits and the high 16 bits int he extent's
	 * pointer to play with.
	 * 
	 * We use these bits to pack the following data in the descriptor:
	 *  - i: The index within the extent, 4 bits truncated.
	 *  - a: The arena index.
	 *  - e: The extent class.
	 *  - p: The extent pointer.
	 * 
	 * 63    56 55    48 47    40 39             8 7      0
	 * iiiiaaaa aaaaaaaa pppppppp [extent pointer] p.eeeeee
	 */
	ulong data;

package:
	this(ulong data) {
		this.data = data;
	}

public:
	this(Extent* extent, ExtentClass ec) {
		// FIXME: in contract.
		assert(isAligned(extent, ExtentAlign), "Invalid Extent alignment!");
		assert(extent.extentClass.data == ec.data, "Invalid ExtentClass!");

		data = ec.data;
		data |= cast(size_t) extent;
		data |= ulong(extent.arenaIndex) << 48;
	}

	this(Extent* extent) {
		// FIXME: in contract.
		assert(!extent.isSlab(), "Extent is a slab!");
		this(extent, ExtentClass.large());
	}

	auto toLeafPayload() const {
		return data;
	}

	@property
	Extent* extent() {
		return cast(Extent*) (data & ExtentMask);
	}

	@property
	uint index() const {
		// FIXME: in contract.
		assert(isSlab(), "Index is only supported for slabs!");

		return data >> 60;
	}

	auto next() const {
		enum Increment = 1UL << 60;
		return PageDescriptor(data + Increment);
	}

	/**
	 * Arena.
	 */
	@property
	uint arenaIndex() const {
		return (data >> 48) & ArenaMask;
	}

	@property
	bool containsPointers() const {
		return (arenaIndex & 0x01) != 0;
	}

	@property
	auto arena() const {
		import d.gc.arena;
		return Arena.getInitialized(arenaIndex);
	}

	/**
	 * Slab features.
	 */
	@property
	auto extentClass() const {
		return ExtentClass(data & ExtentClass.Mask);
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
}

unittest ExtentMap {
	import d.gc.base;
	shared Base base;
	scope(exit) base.clear();

	static shared ExtentMap emap;
	emap.tree.base = &base;

	// We have not mapped anything.
	auto ptr = cast(void*) 0x56789abcd000;
	assert(emap.lookup(ptr).data == 0);

	auto slot = base.allocSlot();
	auto e = Extent.fromSlot(0, slot);
	e.at(ptr, 5 * PageSize, null);

	// Map a range.
	emap.remap(e);
	auto pd = PageDescriptor(e);

	auto end = ptr + e.size;
	for (auto p = ptr; p < end; p += PageSize) {
		assert(emap.lookup(p).data == pd.data);
		pd = pd.next();
	}

	assert(emap.lookup(end).data == 0);

	// Clear a range.
	emap.clear(e);
	for (auto p = ptr; p < end; p += PageSize) {
		assert(emap.lookup(p).data == 0);
	}

	auto ec = ExtentClass.slab(0);
	e.at(ptr, 5 * PageSize, null, ec);
	emap.remap(e, ec);
	pd = PageDescriptor(e, ec);

	for (auto p = ptr; p < end; p += PageSize) {
		assert(emap.lookup(p).data == pd.data);
		pd = pd.next();
	}
}
