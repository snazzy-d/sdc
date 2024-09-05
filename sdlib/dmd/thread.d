module dmd.thread;

import d.gc.types;

extern(C):

// druntime API.
void thread_preSuspend(void* stackTop);
void thread_postSuspend();

void thread_preStopTheWorld();
void thread_postRestartTheWorld();

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
void __sd_gc_thread_scan(ScanDg scan) {
	/**
	 * Note, this is needed, even though druntime will pass in the thread
	 * stacks to scan. The thread calling the collect will have its stack
	 * passed in and added to the worklist (see scanner.d), but by the time the
	 * stack is scanned, it may no longer have the saved registers. Therefore,
	 * we need to scan the registers now.
	 */
	import d.gc.stack;
	scanStack(scan);
}

void __sd_gc_global_scan(ScanDg scan) {
	import d.gc.global;
	// Scan all registered roots and ranges.
	gState.scanRoots(scan);

	thread_scanAll_C(&scan, &__sd_scanAllThreadsFn);
}

void __sd_gc_pre_suspend_hook(void* stackTop) {
	thread_preSuspend(stackTop);
}

void __sd_gc_post_suspend_hook() {
	thread_postSuspend();
}

void __sd_gc_pre_stop_the_world_hook(void* stackTop) {
	thread_preStopTheWorld();
}

void __sd_gc_post_restart_the_world_hook() {
	thread_postRestartTheWorld();
}

// druntime handles this on its own.
void __sd_gc_register_global_segments() {}
void __sd_gc_register_tls_segments() {}
