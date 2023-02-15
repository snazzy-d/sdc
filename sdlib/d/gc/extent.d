module d.gc.extent;

import d.gc.rbtree;
import d.gc.sizeclass;

alias ExtentTree = RBTree!(Extent, addrRangeExtentCmp);

struct Extent {
private:
	ulong bits;

public:
	import d.gc.arena;
	Arena* arena;

	void* addr;
	size_t size;

	// TODO: hpdata?

	// Not necesserly unique, as splitting an Extent
	// Will create two extent with the same serial.
	size_t serialNumber;

	// TODO: Various links for tree, heaps, etc...
	import d.gc.rbtree;
	ExtentTree.Node node;

	// TODO: slab data and/or stats.

public:
	this(Arena* arena, void* addr, size_t size) {
		this.bits = ulong(ClassCount.Total) << 56;

		this.arena = arena;
		this.addr = addr;
		this.size = size;
	}

	this(Arena* arena, void* addr, size_t size, ubyte sizeClass) {
		this.bits = ulong(sizeClass) << 56;

		this.arena = arena;
		this.addr = addr;
		this.size = size;
	}

	@property
	ubyte sizeClass() const {
		ubyte sc = bits >> 56;

		// FIXME: out contract.
		assert(sc < ClassCount.Total);
		return sc;
	}
}

ptrdiff_t addrExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs.addr;
	auto r = cast(size_t) rhs.addr;

	// We need to compare that way to avoid integer overflow.
	return (l > r) - (l < r);
}

ptrdiff_t addrRangeExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs.addr;
	auto rstart = cast(size_t) rhs.addr;
	auto rend = rstart + rhs.size;

	// We need to compare that way to avoid integer overflow.
	return (l >= rend) - (l < rstart);
}

ptrdiff_t sizeAddrExtentCmp(Extent* lhs, Extent* rhs) {
	auto rAddr = cast(size_t) rhs.addr;
	int rSizeClass = rhs.sizeClass;

	int lSizeClass;
	size_t lAddr;
	auto l = cast(size_t) lhs;

	import d.gc.spec;
	if (l & ~PageMask) {
		lAddr = cast(size_t) lhs.addr;
		lSizeClass = lhs.sizeClass;
	} else {
		lAddr = 0;
		lSizeClass = cast(int) (l & PageMask);
	}

	if (lSizeClass != rSizeClass) {
		return lSizeClass - rSizeClass;
	}

	return (lAddr > rAddr) - (lAddr < rAddr);
}
