module dmd.thread;

import d.gc.types;

extern(C):

// druntime API.
bool thread_preSuspend(void* stackTop);
bool thread_postSuspend();

void thread_preStopTheWorld();
void thread_postRestartTheWorld();

void thread_scanAll_C(ScanDg* context, typeof(&__sd_scanAllThreadsFn) scan);

// note, we must interface with DMD using extern(C) calls, so we
// cannot call thread_scanAll directly. This requires a hook compiled
// on the druntime side that forwards to thread_scanAll, and we cannot
// use delegates (as those are not the same ABI)
// the context pointer is just a pass-through for the druntime side, so we
// type it based on what we are passing.
void __sd_scanAllThreadsFn(ScanDg* context, void* start, void* stop) {
	import d.gc.range;
	(*context)(makeRange(start, stop));
}

// sdrt API.
void __sd_gc_global_scan(ScanDg scan) {
	// Scan all registered roots and ranges.
	import d.gc.global;
	gState.scanRoots(scan);

	import d.gc.thread;
	scanSuspendedThreads(scan);

	thread_scanAll_C(&scan, &__sd_scanAllThreadsFn);
}

void __sd_gc_pre_suspend_hook(void* stackTop) {
	if (thread_preSuspend(stackTop)) {
		/**
		 * If the thread is managed by druntime, then we'll get the
		 * TLS segments when calling thread_scanAll_C, so we can remove
		 * them from the thread cache in order to not scan them twice.
		 * 
		 * Note that we cannot do so with the stack, because we need to
		 * scan it eagerly, as registers containing possible pointers gets
		 * pushed on it.
		 */
		import d.gc.tcache;
		threadCache.clearTLSSegments();
	}
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
