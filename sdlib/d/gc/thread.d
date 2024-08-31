module d.gc.thread;

import d.gc.capi;
import d.gc.tcache;

void createProcess() {
	enterBusyState();
	scope(exit) exitBusyState();

	import d.gc.signal;
	setupSignals();

	initThread();

	import d.gc.hooks;
	__sd_gc_register_global_segments();
	__sd_gc_register_tls_segments();
}

void createThread() {
	enterBusyState();
	scope(exit) {
		exitBusyState();
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

void enterBusyState() {
	threadCache.state.enterBusyState();
}

void exitBusyState() {
	threadCache.state.exitBusyState();
}

void stopTheWorld() {
	import d.gc.global;
	gState.stopTheWorld();
}

void restartTheWorld() {
	import d.gc.global;
	gState.restartTheWorld();
}

private:

void initThread() {
	assert(threadCache.state.busy, "Thread is not busy!");

	import d.gc.emap, d.gc.base;
	threadCache.initialize(&gExtentMap, &gBase);

	import d.gc.global;
	gState.register(&threadCache);
}
