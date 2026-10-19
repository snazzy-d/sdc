//T compiles:yes
//T has-passed:yes
//T retval:0
// GC large block finalizer

extern(C) void* __sd_gc_tl_flush_cache();
extern(C) void __sd_gc_collect();

extern(C) void* __sd_gc_alloc_finalizer(size_t size, void* finalizer);
extern(C) void __sd_gc_free(void* ptr);

struct LargeDestructor {
	// ensure a large block
	int[4000] x;

	static int result;

	~this() {
		foreach (v; x) {
			result += v;
		}
	}
}

void destroyItem(void* item, size_t size) {
	assert(size == LargeDestructor.sizeof,
	       "Incorrect size passed to destructor.");
	(cast(LargeDestructor*) item).__dtor();
}

void allocateItem() {
	// allocate a new item, with destroyItem as the finalizer
	auto ptr = __sd_gc_alloc_finalizer(LargeDestructor.sizeof, &destroyItem);

	auto item = cast(LargeDestructor*) ptr;
	foreach (uint i; 0 .. item.x.length) {
		item.x[i] = (i + 10);
	}
}

void main() {
	allocateItem();
	__sd_gc_tl_flush_cache();
	__sd_gc_collect();

	assert(LargeDestructor.result == 8038000, "Destructor did not run.");
}
