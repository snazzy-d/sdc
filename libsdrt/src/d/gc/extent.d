module d.gc.extent;

struct Extent {
	import d.gc.arena;
	Arena* arena;
	
	import d.gc.rbtree;
	Node!Extent node;
	
	void* addr;
	size_t size;
}

ptrdiff_t addrExtentCmp(Extent* lhs, Extent* rhs) {
	auto l = cast(size_t) lhs.addr;
	auto r = cast(size_t) rhs.addr;
	
	// We need to compare that way to avoid integer overflow.
	return (l > r) - (l < r);
}
