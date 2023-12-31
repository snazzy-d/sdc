module core.stdc.dlfcn;

/**
 * FIXME:
 * Ideally, we'd want the following:
 *   enum RTLD_DEFAULT = cast(void*) 0;
 *   enum RTLD_NEXT = cast(void*) -1L;
 *
 * but SDC currently does not support integral to
 * pointer casts at compile time. Instead, we use
 * properties that emulate the desired behavior.
 */
@property
auto RTLD_DEFAULT() {
	return cast(void*) 0;
}

@property
auto RTLD_NEXT() {
	return cast(void*) -1L;
}

extern(C):

void* dlsym(void* handle, const char* symbol);
