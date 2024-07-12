module dmd.thread;

alias ScanDg = void delegate(const(void*)[] range);

extern(C):

// druntime API.
void thread_suspendAll();
void thread_resumeAll();
void thread_scanAll_C(ScanDg* context, typeof(&__sd_scanAllThreadsFn) scan);

// note, we must interface with DMD using extern(C) calls, so we
// cannot call thread_scanAll directly. This requires a hook compiled
// on the druntime side that forwards to thread_scanAll, and we cannot
// use delegates (as those are not the same ABI)
// the context pointer is just a pass-through for the druntime side, so we
// type it based on what we are passing.
void __sd_scanAllThreadsFn(ScanDg* context, void* start, void* end) {
	import d.gc.range;
	(*context)(makeRange(start, end));
}

// sdrt API.
void __sd_thread_scan(ScanDg scan) {
	// When druntime is being used, all thread scanning is done by
	// thread_scanAll_C, and not via SDC's thread scanning.
}

void __sd_global_scan(ScanDg scan) {
	import d.gc.global;
	// Scan all registered roots and ranges.
	gState.scanRoots(scan);

	thread_scanAll_C(&scan, &__sd_scanAllThreadsFn);
}

void __sd_thread_stop_the_world() {
	thread_suspendAll();
}

void __sd_thread_restart_the_world() {
	thread_resumeAll();
}

void __sd_thread_create() {
	import d.gc.capi;
	__sd_gc_init();
}

void __sd_thread_destroy() {
	import d.gc.capi;
	__sd_gc_destroy_thread();
}
