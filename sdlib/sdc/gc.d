module sdc.gc;

import d.gc.types;

extern(C):

void __sd_gc_thread_scan(ScanDg scan) {
	// Scan the registered TLS segments.
	import d.gc.tcache;
	foreach (s; threadCache.tlsSegments) {
		scan(s);
	}

	import d.gc.stack;
	scanStack(scan);
}

void __sd_gc_global_scan(ScanDg scan) {
	import d.gc.global;
	gState.scanRoots(scan);
}

void __sd_gc_pre_suspend_hook(void* stackTop) {}
void __sd_gc_post_suspend_hook() {}

void __sd_gc_register_global_segments() {
	import d.rt.elf;
	registerGlobalSegments();
}

void __sd_gc_register_tls_segments() {
	import d.rt.elf;
	registerTlsSegments();
}
