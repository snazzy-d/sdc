module d.gc.extent;

import d.gc.rbtree;
alias ExtentTree = RBTree!(Extent, addrRangeExtentCmp);

struct Extent {
	import d.gc.arena;
	Arena* arena;

	import d.gc.rbtree;
	ExtentTree.Node node;

	void* addr;
	size_t size;
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
