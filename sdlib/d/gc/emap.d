module d.gc.emap;

import d.gc.extent;
import d.gc.spec;
import d.gc.util;

shared ExtentMap extentMap;

struct ExtentMap {
private:
	import d.gc.rtree;
	RTree!PageDescriptor tree;

public:
	PageDescriptor lookup(void* addr) shared {
		auto leaf = tree.get(addr);
		return leaf is null ? PageDescriptor(0) : leaf.load();
	}

	void remap(Extent* extent) shared {
		batchMapImpl(extent, PageDescriptor(extent, false));
	}

	void clear(Extent* extent) shared {
		batchMapImpl(extent, PageDescriptor(0));
	}

private:
	void batchMapImpl(Extent* extent, PageDescriptor pd) shared {
		// FIXME: in contract.
		assert(isAligned(extent.addr, PageSize),
		       "Incorrectly aligned extent.addr!");
		assert(isAligned(extent.size, PageSize),
		       "Incorrectly aligned extent.size!");

		auto start = extent.addr;
		auto stop = start + extent.size;

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
	this(Extent* extent, bool is_slab) {
		this(is_slab | cast(ulong) extent);
	}

	auto toLeafPayload() const {
		return data;
	}

	@property
	Extent* extent() {
		return cast(Extent*) (data & ~0x01);
	}

	bool isSlab() const {
		return (data & 0x01) != 0;
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

	Extent e;
	e.addr = ptr;
	e.size = 5 * PageSize;

	// Map a range.
	emap.remap(&e);
	auto pd = PageDescriptor(&e, false);

	auto end = ptr + e.size;
	for (auto p = ptr; p < end; p += PageSize) {
		assert(emap.lookup(p).data == pd.data);
	}

	assert(emap.lookup(end).data == 0);

	// Clear a range.
	emap.clear(&e);
	for (auto p = ptr; p < end; p += PageSize) {
		assert(emap.lookup(p).data == 0);
	}
}
