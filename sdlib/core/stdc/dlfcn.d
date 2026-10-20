module core.stdc.dlfcn;

enum RTLD_DEFAULT = cast(void*) 0;

/**
 * FIXME: Ideally, we'd want the following:
 *   enum RTLD_NEXT = cast(void*) -1L;
 *
 * but SDC currently does not fold the negation before casting.
 * Instead, we use a property that emulates the desired behavior.
 */
@property
auto RTLD_NEXT() {
	return cast(void*) -1L;
}

extern(C):

void* dlsym(void* handle, const char* symbol);
