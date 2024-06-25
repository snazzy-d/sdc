//T compiles:yes
//T has-passed:yes
//T retval:0
// GC large block finalizer

extern(C) void __sd_gc_collect();
extern(C) void* __sd_gc_alloc_finalizer(size_t size, void* finalizer);

struct LargeDestructor {
	int[4000] x; // ensure a large block

	static int result;

	~this() {
		foreach (v; x)
			result += v;
	}
}

void destroyItem(void* item, size_t size) {
	assert(size == LargeDestructor.sizeof,
	       "incorrect size passed to destructor");
	(cast(LargeDestructor*) item).__dtor();
}

void allocateItem() {
	// allocate a new item, with destroyItem as the finalizer
	LargeDestructor* item = cast(LargeDestructor*)
		__sd_gc_alloc_finalizer(LargeDestructor.sizeof, &destroyItem);

	foreach (uint i; 0 .. item.x.length) {
		item.x[i] = (i + 10);
	}
}

void killstack() {
	ubyte[1000] buf;
	memset(buf.ptr, 0xff, buf.length);
}

void main() {
	allocateItem();
	killstack();
	__sd_gc_collect();
	assert(LargeDestructor.result == 8038000, "Destructor did not run");
}
