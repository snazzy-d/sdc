module d.gc.capi;

import d.gc.tcache;

extern(C):

/**
 * Standard C allocating functions.
 */
/+
void* malloc(size_t size) {
	return threadCache.alloc(size, true, false);
}

void free(void* ptr) {
	threadCache.free(ptr);
}

void* calloc(size_t nmemb, size_t size) {
	return threadCache.alloc(nmemb * size, true, true);
}

void* realloc(void* ptr, size_t size) {
	return threadCache.realloc(ptr, size, true);
}
// +/

/**
 * Setup.
 */
void __sd_gc_init() {
	import d.gc.emap, d.gc.base;
	threadCache.initialize(&gExtentMap, &gBase);
}

void __sd_gc_destroy_thread() {
	threadCache.destroyThread();
}

/**
 * SDC runtime API.
 */
void* __sd_gc_alloc(size_t size) {
	return threadCache.alloc(size, true, false);
}

void* __sd_gc_array_alloc(size_t size) {
	return __sd_gc_alloc(size);
}

void __sd_gc_free(void* ptr) {
	threadCache.free(ptr);
}

void __sd_gc_destroy(void* ptr) {
	threadCache.destroy(ptr);
}

void* __sd_gc_realloc(void* ptr, size_t size) {
	return threadCache.realloc(ptr, size, true);
}

void __sd_gc_tl_flush_cache() {
	threadCache.flushCache();
}

/**
 * Garbage collection cycles.
 */
void __sd_gc_collect() {
	threadCache.runGCCycle();
}

void __sd_gc_add_roots(const void[] range) {
	import d.gc.global;
	gState.addRoots(range);
}

void __sd_gc_add_tls_segment(const void[] range) {
	threadCache.addTLSSegment(range);
}
