module d.finalizer;

// SDC implementation of finalizer for the GC.

extern(C)
void __sd_run_finalizer(void* ptr, size_t usedSpace, void* finalizer) {
	alias FinalizerFunctionType = void function(void* ptr, size_t size);
	(cast(FinalizerFunctionType) finalizer)(ptr, usedSpace);
}
