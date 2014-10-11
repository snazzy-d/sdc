module d.rt.druntimestub;

extern(C):

void* _d_allocmemory(size_t size) {
	return malloc(size);
}

void _d_assert(string, int) {
	exit(1);
}

void _d_assert_msg(string, string, int) {
	exit(1);
}

void _d_arraybounds(string, int) {
	exit(1);
}

