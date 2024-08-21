module d.gc.capi;

import d.gc.tcache;

extern(C):

/**
 * Standard C allocating functions.
 */
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

/**
 * Setup.
 */
void __sd_gc_init() {
	assert(threadCache.state.busy, "Thread is not busy!");

	import d.gc.emap, d.gc.base;
	threadCache.initialize(&gExtentMap, &gBase);

	import d.gc.global;
	gState.register(&threadCache);
}

void __sd_gc_destroy_thread() {
	threadCache.destroyThread();

	import d.gc.global;
	gState.remove(&threadCache);
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

void* __sd_gc_alloc_finalizer(size_t size, void* finalizer) {
	return threadCache.allocAppendable(size, true, false, finalizer);
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
 * Thread suspesion API.
 */
void __sd_gc_thread_enter_busy_state() {
	threadCache.state.enterBusyState();
}

void __sd_gc_thread_exit_busy_state() {
	threadCache.state.exitBusyState();
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

void __sd_gc_remove_roots(const void* ptr) {
	import d.gc.global;
	gState.removeRoots(ptr);
}

void __sd_gc_add_tls_segment(const void[] range) {
	threadCache.addTLSSegment(range);
}
