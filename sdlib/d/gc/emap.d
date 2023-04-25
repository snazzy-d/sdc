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

	void remap(Extent* extent, bool is_slab, ubyte sizeClass) shared {
		batchMapImpl(extent.addr, extent.size,
		             PageDescriptor(extent, is_slab, sizeClass));
	}

	void remap(Extent* extent, ubyte sizeClass) shared {
		// FIXME: in contract.
		assert(extent.isSlab(), "Extent is expected to be a slab!");
		assert(extent.sizeClass == sizeClass, "Invalid size class!");

		remap(extent, true, sizeClass);
	}

	void remap(Extent* extent) shared {
		// FIXME: in contract.
		assert(!extent.isSlab(), "Extent is a slab!");

		// FIXME: Overload resolution doesn't cast this properly.
		remap(extent, false, ubyte(0));
	}

	void clear(Extent* extent) shared {
		batchMapImpl(extent.addr, extent.size, PageDescriptor(0));
	}

private:
	void batchMapImpl(void* address, size_t size, PageDescriptor pd) shared {
		// FIXME: in contract.
		assert(isAligned(address, PageSize), "Incorrectly aligned address!");
		assert(isAligned(size, PageSize), "Incorrectly aligned size!");

		auto start = address;
		auto stop = start + size;

		for (auto ptr = start; ptr < stop; ptr += PageSize) {
			// FIXME: batch set, so we don't need L0 lookup again and again.
			tree.set(ptr, pd);
		}
	}
}

struct PageDescriptor {
private:
	ulong data;

package:
	this(ulong data) {
		this.data = data;
	}

public:
	this(Extent* extent, bool is_slab, ubyte sizeClass) {
		// FIXME: in contract.
		assert(isAligned(extent, ExtentAlign), "Invalid Extent alignment!");

		data = is_slab;
		data |= cast(size_t) extent;
		data |= ulong(sizeClass) << 58;
	}

	this(Extent* extent, ubyte sizeClass) {
		// FIXME: in contract.
		assert(extent.isSlab(), "Extent is expected to be a slab!");
		assert(extent.sizeClass == sizeClass, "Invalid size class!");

		this(extent, true, sizeClass);
	}

	this(Extent* extent) {
		// FIXME: in contract.
		assert(!extent.isSlab(), "Extent is a slab!");

		// FIXME: Overload resolution doesn't cast this properly.
		this(extent, false, ubyte(0));
	}

	auto toLeafPayload() const {
		return data;
	}

	@property
	Extent* extent() {
		return cast(Extent*) (data & ExtentMask);
	}

	bool isSlab() const {
		return (data & 0x01) != 0;
	}

	@property
	ubyte sizeClass() const {
		// FIXME: in contract.
		assert(isSlab(), "slabData accessed on non slab!");

		ubyte sc = data >> 58;

		// FIXME: out contract.
		import d.gc.sizeclass;
		assert(sc < ClassCount.Small);
		return sc;
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
	auto e = Extent.fromSlot(null, slot);
	e.at(ptr, 5 * PageSize, null);

	// Map a range.
	emap.remap(e);
	auto pd = PageDescriptor(e);

	auto end = ptr + e.size;
	for (auto p = ptr; p < end; p += PageSize) {
		assert(emap.lookup(p).data == pd.data);
	}

	assert(emap.lookup(end).data == 0);

	// Clear a range.
	emap.clear(e);
	for (auto p = ptr; p < end; p += PageSize) {
		assert(emap.lookup(p).data == 0);
	}
}
