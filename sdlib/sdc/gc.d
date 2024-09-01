module sdc.gc;

extern(C):

void __sd_gc_register_global_segments() {
	import d.rt.elf;
	registerGlobalSegments();
}

void __sd_gc_register_tls_segments() {
	import d.rt.elf;
	registerTlsSegments();
}
