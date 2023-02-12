module d.gc.extent;

import d.gc.rbtree;
import d.gc.sizeclass;

alias ExtentTree = RBTree!(Extent, addrRangeExtentCmp);

struct Extent {
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
	int rBinID = getBinID(rhs.size + 1) - 1;

	int lBinID;
	size_t lAddr;
	auto l = cast(size_t) lhs;

	import d.gc.spec;
	if (l & ~PageMask) {
		lAddr = cast(size_t) lhs.addr;
		lBinID = getBinID(lhs.size + 1) - 1;
	} else {
		lAddr = 0;
		lBinID = cast(int) (l & PageMask);
	}

	if (lBinID != rBinID) {
		return lBinID - rBinID;
	}

	return (lAddr > rAddr) - (lAddr < rAddr);
}
