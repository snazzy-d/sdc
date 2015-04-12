module d.rt.thread;

extern(C) void __sd_thread_init() {
	_tl_gc_set_stack_bottom(getStackBottom());
}

private:

version(linux) {
	void* getStackBottom() {
		pthread_attr_t attr;
		void* addr; size_t size;
		
		if (pthread_getattr_np(pthread_self(), &attr)) {
			printf("pthread_getattr_np failed!".ptr);
			exit(1);
		}
		
		if (pthread_attr_getstack(&attr, &addr, &size)) {
			printf("pthread_attr_getstack failed!".ptr);
			exit(1);
		}
		
		if (pthread_attr_destroy(&attr)) {
			printf("pthread_attr_destroy failed!".ptr);
			exit(1);
		}
		
		return addr + size;
	}
}

version(OSX) {
	void* getStackBottom() {
		return pthread_get_stackaddr_np(pthread_self());
	}
}

// XXX: Will do for now.
alias pthread_t = size_t;
union pthread_attr_t {
	size_t t;
	ubyte[6 * size_t.sizeof + 8] d;
}

extern(C):

pthread_t pthread_self();

version(linux) {
	int pthread_getattr_np(pthread_t __th, pthread_attr_t* __attr);
	int pthread_attr_getstack(const pthread_attr_t* __attr, void** __stackaddr, size_t* __stacksize);
	int pthread_attr_destroy(pthread_attr_t* __attr);
}

version(OSX) {
	void* pthread_get_stackaddr_np(pthread_t __th);
}

void _tl_gc_set_stack_bottom(const void* bottom);

