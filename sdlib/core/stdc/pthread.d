module core.stdc.pthread;

// XXX: Will do for now.
alias pthread_t = size_t;
union pthread_attr_t {
	size_t t;
	ubyte[6 * size_t.sizeof + 8] d;
}

extern(C):

pthread_t pthread_self();
int pthread_create(pthread_t* thread, const pthread_attr_t* attr,
                   void* function(void*) start_routine, void* arg);
int pthread_cancel(pthread_t thread);
int pthread_join(pthread_t th, void** thread_return);

version(linux) {
	int pthread_getattr_np(pthread_t __th, pthread_attr_t* __attr);
	int pthread_attr_getstack(const pthread_attr_t* __attr, void** __stackaddr,
	                          size_t* __stacksize);
	int pthread_attr_destroy(pthread_attr_t* __attr);
}

version(OSX) {
	void* pthread_get_stackaddr_np(pthread_t __th);
}

version(FreeBSD) {
	int pthread_attr_init(pthread_attr_t*);
	int pthread_attr_get_np(pthread_t, pthread_attr_t*);
	int pthread_attr_getstack(pthread_attr_t*, void**, size_t*);
	int pthread_attr_destroy(pthread_attr_t*);
}
