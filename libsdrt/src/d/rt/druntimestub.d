module d.rt.druntimestub;

extern(C):

void* __sd_gc_tl_malloc(size_t size);

void* __sd_array_alloc(size_t size) {
	return __sd_gc_tl_malloc(size);
}

void _d_assert(string file, int line) {
	printf("assert fail: %s:%d\n".ptr, file.ptr, line);
	exit(1);
}

void _d_assert_msg(string msg, string file, int line) {
	printf("%s: %s:%d\n".ptr, msg.ptr, file.ptr, line);
	exit(1);
}
