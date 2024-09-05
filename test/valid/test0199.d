//T compiles:yes
//T has-passed:yes
//T retval:0
// GC add/remove single root

extern(C) void* __sd_gc_tl_flush_cache();
extern(C) void __sd_gc_collect();

extern(C) void* __sd_gc_alloc_finalizer(size_t size, void* finalizer);
extern(C) void __sd_gc_free(void* ptr);

int finalizerCalled;

void finalize(void* ptr, size_t size) {
	++finalizerCalled;
}

size_t allocate(bool pin) {
	auto ptr = __sd_gc_alloc_finalizer(16, &finalize);
	auto iptr = cast(size_t) ptr;
	scope(exit) {
		ptr = null;
		iptr = 0;
	}

	enum BlockSize = 2 * 1024 * 1024;
	if ((iptr % BlockSize) == 0) {
		// The pointer is aligned on a block, this tend to lead to
		// false positive. To avoid this, we'll get a new one.
		scope(exit) __sd_gc_free(ptr);
		return allocate(pin);
	}

	if (pin) {
		import d.gc.global;
		gState.addRoots(ptr[0 .. 0]);
	}

	return ~iptr;
}

void unpin(size_t blk) {
	import d.gc.global;
	gState.removeRoots(cast(void*) ~blk);
}

void main() {
	auto blk = allocate(false);
	__sd_gc_tl_flush_cache();
	__sd_gc_collect();
	assert(finalizerCalled == 1, "Finalizer not called when unpinned.");
	blk = allocate(true);
	__sd_gc_tl_flush_cache();
	__sd_gc_collect();
	assert(finalizerCalled == 1, "Finalizer called when pinned.");
	unpin(blk);
	__sd_gc_tl_flush_cache();
	__sd_gc_collect();
	assert(finalizerCalled == 2, "Finalizer not called after unpinning.");
}
