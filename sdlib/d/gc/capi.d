module d.gc.capi;

import d.gc.tcache;

extern(C):

/**
 * Standard C allocating functions.
 */
void* malloc(size_t size) {
	return threadCache.alloc(size, true);
}

void free(void* ptr) {
	threadCache.free(ptr);
}

void* calloc(size_t nmemb, size_t size) {
	return threadCache.calloc(nmemb * size, true);
}

void* realloc(void* ptr, size_t size) {
	return threadCache.realloc(ptr, size, true);
}

/**
 * SDC runtime API.
 */
void* __sd_gc_alloc(size_t size) {
	return threadCache.alloc(size, true);
}

void* __sd_gc_array_alloc(size_t size) {
	return __sd_gc_alloc(size);
}

void __sd_gc_free(void* ptr) {
	threadCache.free(ptr);
}

void* __sd_gc_realloc(void* ptr, size_t size) {
	return threadCache.realloc(ptr, size, true);
}

void __sd_gc_set_stack_bottom(const void* bottom) {
	threadCache.stackBottom = makeRange(bottom[0 .. 0]).ptr;
}

void __sd_gc_add_roots(const void[] range) {
	threadCache.addRoots(range);
}

void __sd_gc_collect() {
	threadCache.collect();
}
