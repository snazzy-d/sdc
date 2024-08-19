module d.rt.trampoline;

import core.stdc.pthread;

alias PthreadFunction = void* function(void*);

// Hijack the system's pthread_create function so we can register the thread.
extern(C) int pthread_create(pthread_t* thread, const pthread_attr_t* attr,
                             PthreadFunction start_routine, void* arg) {
	// It is probably best to avoid stopping a thread in the middle
	// of another thread's creation.
	__sd_gc_thread_enter_busy_state();
	scope(exit) __sd_gc_thread_exit_busy_state();

	return pthread_create_trampoline(
		thread, attr, cast(PthreadFunction) runThread,
		new ThreadRunner(start_routine, arg));
}

private:

extern(C) void __sd_thread_create();
extern(C) void __sd_thread_destroy();
extern(C) void __sd_gc_free(void* ptr);

extern(C) void __sd_gc_thread_enter_busy_state();
extern(C) void __sd_gc_thread_exit_busy_state();

struct ThreadRunner {
	void* arg;
	void* function(void*) fun;

	this(void* function(void*) fun, void* arg) {
		this.arg = arg;
		this.fun = fun;
	}
}

void destroyThread(void* dummy) {
	__sd_thread_destroy();
}

void* runThread(ThreadRunner* runner) {
	auto fun = runner.fun;
	auto arg = runner.arg;

	__sd_thread_create();
	__sd_gc_free(runner);

	// Make sure we clean up after ourselves.
	scope(exit) __sd_thread_destroy();

	return fun(arg);
}

alias PthreadCreateType =
	int function(pthread_t* thread, const pthread_attr_t* attr,
	             PthreadFunction start_routine, void* arg);

shared
PthreadCreateType pthread_create_shared_trampoline = resolve_pthread_create;

@property
ref PthreadCreateType pthread_create_trampoline() {
	return *(cast(PthreadCreateType*) &pthread_create_shared_trampoline);
}

int resolve_pthread_create(pthread_t* thread, const pthread_attr_t* attr,
                           PthreadFunction start_routine, void* arg) {
	PthreadCreateType real_pthread_create;

	// First, check if there is an interceptor and if so, use it.
	// This ensure we remain compatible with sanitizers, as they use
	// a similar trick to intercept various library calls.
	import core.stdc.dlfcn;
	real_pthread_create = cast(PthreadCreateType)
		dlsym(RTLD_DEFAULT, "__interceptor_pthread_create");
	if (real_pthread_create !is null) {
		goto Forward;
	}

	// It doesn't look like we have an interceptor, forward to the method
	// in the next object.
	real_pthread_create =
		cast(PthreadCreateType) dlsym(RTLD_NEXT, "pthread_create");
	if (real_pthread_create is null) {
		import core.stdc.stdlib, core.stdc.stdio;
		printf("Failed to locate pthread_create!");
		exit(1);
	}

Forward:
	// Rebind the trampoline so we never resolve again.
	pthread_create_trampoline = real_pthread_create;
	return real_pthread_create(thread, attr, start_routine, arg);
}
