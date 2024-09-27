//T compiles:yes
//T has-passed:yes
//T retval:0
// GC multithreaded stress test.

import core.stdc.pthread;

extern(C) void __sd_gc_collect();
extern(C) void* __sd_gc_alloc(size_t size);
extern(C) void __sd_gc_tl_activate(bool activated);

void randomAlloc() {
	// These thread generate garbage as an incredible rate,
	// so we do not trigger collection automatically.
	__sd_gc_tl_activate(false);

	enum CollectCycle = 4 * 1024 * 1024;
	size_t n = 11400714819323198485;
	n ^= cast(size_t) pthread_self();

	foreach (_; 0 .. 8) {
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

void* runThread(void*) {
	randomAlloc();
	return null;
}

void main() {
	enum ThreadCount = 4;
	pthread_t[ThreadCount - 1] tids;

	foreach (ref tid; tids) {
		pthread_create(&tid, null, runThread, null);
	}

	randomAlloc();

	foreach (ref tid; tids) {
		void* ret;
		pthread_join(tid, &ret);
	}
}
