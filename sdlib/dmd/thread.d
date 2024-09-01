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
	/**
	 * Note, this is needed, even though druntime will pass in the thread
	 * stacks to scan. The thread calling the collect will have its stack
	 * passed in and added to the worklist (see scanner.d), but by the time the
	 * stack is scanned, it may no longer have the saved registers. Therefore,
	 * we need to scan the registers now.
	 */
	import d.rt.stack;
	__sd_stack_scan(scan);
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

extern(C) void __sd_thread_creation_enter() {
	import d.gc.global;
	gState.enterThreadCreation();
}

extern(C) void __sd_thread_creation_exit() {
	import d.gc.global;
	gState.exitThreadCreation();
}

void __sd_thread_create() {
	import d.gc.capi;
	__sd_gc_thread_enter_busy_state();
	scope(exit) {
		__sd_gc_thread_exit_busy_state();
		__sd_thread_creation_exit();
	}

	__sd_gc_init();
}
