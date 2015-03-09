module d.rt.druntimestub;

extern(C):

void* _tl_gc_alloc(size_t size);

void* _d_allocmemory(size_t size) {
	return _tl_gc_alloc(size);
}

void _d_assert(string file, int line) {
	printf("assert fail: %s:%d\n".ptr, file.ptr, line);
	exit(1);
}

void _d_assert_msg(string msg, string file, int line) {
	printf("%s: %s:%d\n".ptr, msg.ptr, file.ptr, line);
	exit(1);
}

void _d_arraybounds(string file, int line) {
	printf("bound check fail: %s:%d\n".ptr, file.ptr, line);
	exit(1);
}

