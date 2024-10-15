//T compiles:yes
//T has-passed:yes
//T retval:0
// GC addRoot reentrancy test.

extern(C) void* __sd_gc_alloc(size_t size);
extern(C) void __sd_gc_add_roots(const void[] range);

void main() {
	foreach (i; 0 .. 256) {
		enum BufferSize = 800_000_000;

		// Get the GC close past a collect threshold.
		auto ptr = __sd_gc_alloc(BufferSize);
		__sd_gc_add_roots(ptr[0 .. BufferSize]);
	}
}
