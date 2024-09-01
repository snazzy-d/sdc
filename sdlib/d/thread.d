module d.thread;

alias ScanDg = void delegate(const(void*)[] range);
extern(C) void __sd_thread_scan(ScanDg scan) {
	// Scan the registered TLS segments.
	import d.gc.tcache;
	foreach (s; threadCache.tlsSegments) {
		scan(s);
	}

	import d.gc.stack;
	scanStack(scan);
}

extern(C) void __sd_global_scan(ScanDg scan) {
	import d.gc.global;
	gState.scanRoots(scan);
}

extern(C) void __sd_thread_stop_the_world() {
	import d.gc.global;
	gState.stopTheWorld();
}

extern(C) void __sd_thread_restart_the_world() {
	import d.gc.global;
	gState.restartTheWorld();
}
