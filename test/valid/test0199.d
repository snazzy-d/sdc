//T compiles:yes
//T has-passed:yes
//T retval:0
// GC add/remove single root

extern(C) void __sd_gc_collect();
extern(C) void* __sd_gc_alloc_finalizer(size_t size, void* finalizer);
extern(C) void* __sd_gc_tl_flush_cache();

int finalizerCalled;

void finalize(void* ptr, size_t size) {
	++finalizerCalled;
}

size_t allocate(bool pin) {
	auto ptr = __sd_gc_alloc_finalizer(16, &finalize);
	size_t retval = ~cast(size_t) ptr;

	if (pin) {
		import d.gc.global;
		gState.addRoots(ptr[0 .. 0]);
	}

	ptr = null;
	return retval;
}

void unpin(size_t blk) {
	import d.gc.global;
	gState.removeRoots(cast(void*) ~blk);
}

void main() {
	// NOTE: the first slab block allocated is never collected, because it
	// appears on the stack during collection. Until this bug is fixed, consume
	// the first allocation.
	auto ptr = __sd_gc_alloc_finalizer(16, null);

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
