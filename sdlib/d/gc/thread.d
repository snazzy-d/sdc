module d.gc.thread;

import d.gc.capi;
import d.gc.tcache;

void createProcess() {
	__sd_gc_thread_enter_busy_state();
	scope(exit) __sd_gc_thread_exit_busy_state();

	import d.gc.signal;
	setupSignals();

	initThread();

	import d.gc.hooks;
	__sd_gc_register_global_segments();
	__sd_gc_register_tls_segments();
}

void createThread() {
	__sd_gc_thread_enter_busy_state();
	scope(exit) {
		__sd_gc_thread_exit_busy_state();
		exitThreadCreation();
	}

	initThread();

	import d.gc.hooks;
	__sd_gc_register_tls_segments();
}

void destroyThread() {
	threadCache.destroyThread();

	import d.gc.global;
	gState.remove(&threadCache);
}

void enterThreadCreation() {
	import d.gc.global;
	gState.enterThreadCreation();
}

void exitThreadCreation() {
	import d.gc.global;
	gState.exitThreadCreation();
}

private:

void initThread() {
	assert(threadCache.state.busy, "Thread is not busy!");

	import d.gc.emap, d.gc.base;
	threadCache.initialize(&gExtentMap, &gBase);

	import d.gc.global;
	gState.register(&threadCache);
}
