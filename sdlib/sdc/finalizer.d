module sdc.finalizer;

extern(C):

alias FinalizerFunctionType = void function(void* ptr, size_t size);
void __sd_gc_finalize(void* ptr, size_t usedSpace, void* finalizer) {
	(cast(FinalizerFunctionType) finalizer)(ptr, usedSpace);
}
