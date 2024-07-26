module d.rt.trampoline;

import core.stdc.pthread;

alias PthreadFunction = void* function(void*);

// Hijack the system's pthread_create function so we can register the thread.
extern(C) int pthread_create(pthread_t* thread, const pthread_attr_t* attr,
                             PthreadFunction start_routine, void* arg) {
	auto runner = ThreadRunner(start_routine, arg);

	auto result =
		pthread_create_trampoline(thread, attr, cast(PthreadFunction) runThread,
		                          &runner);

	if (result == 0) {
		runner.waitForRelease();
	} else {
		runner.release();
	}

	return result;
}

private:

struct ThreadRunner {
	void* arg;
	void* function(void*) fun;

	import d.sync.mutex;
	shared Mutex mutex;

	this(void* function(void*) fun, void* arg) {
		this.arg = arg;
		this.fun = fun;

		mutex.lock();
	}

	void release() {
		mutex.unlock();
	}

	void waitForRelease() {
		mutex.lock();
		release();
	}
}

extern(C) void __sd_thread_create();
extern(C) void __sd_thread_destroy();

void destroyThread(void* dummy) {
	__sd_thread_destroy();
}

void* runThread(ThreadRunner* runner) {
	auto fun = runner.fun;
	auto arg = runner.arg;

	runner.release();

	// Make sure we clean up after ourselves.
	scope(exit) __sd_thread_destroy();
	__sd_thread_create();

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
