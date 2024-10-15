//T compiles:yes
//T has-passed:yes
//T retval:0
// GC add/remove single root

extern(C) void* __sd_gc_tl_flush_cache();
extern(C) void __sd_gc_collect();

extern(C) void* __sd_gc_alloc_finalizer(size_t size, void* finalizer);
extern(C) void __sd_gc_free(void* ptr);

extern(C) void __sd_gc_add_roots(const void[] range);
extern(C) void __sd_gc_remove_roots(const void* ptr);

int finalizerCalled;

void finalize(void* ptr, size_t size) {
	++finalizerCalled;
}

size_t allocate(bool pin) {
	auto ptr = __sd_gc_alloc_finalizer(16, &finalize);

	if (pin) {
		__sd_gc_add_roots(ptr[0 .. 0]);
	}

	return ~(cast(size_t) ptr);
}

void unpin(size_t blk) {
	__sd_gc_remove_roots(cast(void*) ~blk);
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
