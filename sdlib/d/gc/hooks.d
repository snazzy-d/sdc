module d.gc.hooks;

import d.gc.types;

extern(C):

void __sd_gc_global_scan(ScanDg scan);

void __sd_gc_pre_suspend_hook(void* stackTop);
void __sd_gc_post_suspend_hook();

void __sd_gc_pre_stop_the_world_hook(void* stackTop);
void __sd_gc_post_restart_the_world_hook();

void __sd_gc_finalize(void* ptr, size_t usedSpace, void* finalizer);

void __sd_gc_register_global_segments();
