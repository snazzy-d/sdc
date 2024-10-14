//T compiles:yes
//T has-passed:yes
//T retval:0
// GC stress test.

extern(C) void __sd_gc_collect();
extern(C) void* __sd_gc_alloc(size_t size);
extern(C) void __sd_gc_tl_activate(bool activated);

void main() {
	// We generate garbage at an alarming rate,
	// so we do not trigger collection automatically.
	__sd_gc_tl_activate(false);

	enum CollectCycle = 10000000;
	size_t n = 11400714819323198485;

	foreach (loop; 0 .. 20) {
		foreach (i; 0 .. CollectCycle) {
			n = n * 6364136223846793005 + 1442695040888963407;

			auto x = (i + 1) << 5;
			auto m = (x & -x) - 1;
			auto s = n & m;

			__sd_gc_alloc(s);
		}

		__sd_gc_collect();
	}
}
