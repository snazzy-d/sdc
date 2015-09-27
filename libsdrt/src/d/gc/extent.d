module d.gc.extent;

import d.gc.rbtree;
alias ExtentTree = RBTree!(Extent, addrExtentCmp);
alias LookupExtentTree = RBTree!(Extent, addrExtentCmp, "lookupNode");

struct Extent {
	import d.gc.arena;
	Arena* arena;
	
	import d.gc.rbtree;
	ExtentTree.Node node;
	
	// Used for GC lookup of huge allocs.
	LookupExtentTree.Node lookupNode;
	
	void* addr;
	size_t size;
}

ptrdiff_t addrExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs.addr;
	auto r = cast(size_t) rhs.addr;
	
	// We need to compare that way to avoid integer overflow.
	return (l > r) - (l < r);
}
