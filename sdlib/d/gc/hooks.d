module d.gc.hooks;

extern(C):

void __sd_gc_finalize(void* ptr, size_t usedSpace, void* finalizer);

void __sd_gc_register_global_segments();
void __sd_gc_register_tls_segments();
