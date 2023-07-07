module d.rt.thread;

extern(C) void __sd_thread_init() {
	__sd_gc_set_stack_bottom(getStackBottom());
	registerTlsSegments();
}

private:

version(linux) {
	void* getStackBottom() {
		pthread_attr_t attr;
		void* addr;
		size_t size;

		if (pthread_getattr_np(pthread_self(), &attr)) {
			import core.stdc.stdlib, core.stdc.stdio;
			printf("pthread_getattr_np failed!");
			exit(1);
		}

		if (pthread_attr_getstack(&attr, &addr, &size)) {
			import core.stdc.stdlib, core.stdc.stdio;
			printf("pthread_attr_getstack failed!");
			exit(1);
		}

		if (pthread_attr_destroy(&attr)) {
			import core.stdc.stdlib, core.stdc.stdio;
			printf("pthread_attr_destroy failed!");
			exit(1);
		}

		return addr + size;
	}

	import sys.linux.link;

	void registerTlsSegments() {
		dl_iterate_phdr(callback, null);
	}

	extern(C) int callback(dl_phdr_info* info, size_t size, void* data) {
		auto tlsStart = info.dlpi_tls_data;
		if (tlsStart is null) {
			// FIXME: make sure this is not lazy initialized or something.
			return 0;
		}

		// Force materialization. (work around a bug, evil sayers may say)
		ElfW!"Phdr" dummy;

		auto segmentCount = info.dlpi_phnum;
		foreach (i; 0 .. segmentCount) {
			auto segment = info.dlpi_phdr[i];

			import sys.linux.elf;
			if (segment.p_type != PT_TLS) {
				continue;
			}

			__sd_gc_add_roots(tlsStart[0 .. segment.p_memsz]);
		}

		return 0;
	}
}

version(OSX) {
	void* getStackBottom() {
		return pthread_get_stackaddr_np(pthread_self());
	}

	extern(C) void _d_dyld_registerTLSRange();

	void registerTlsSegments() {
		_d_dyld_registerTLSRange();
	}
}

version(FreeBSD) {
	void* getStackBottom() {
		pthread_attr_t attr;
		void* addr;
		size_t size;

		pthread_attr_init(&attr);
		pthread_attr_get_np(pthread_self(), &attr);
		pthread_attr_getstack(&attr, &addr, &size);
		pthread_attr_destroy(&attr);
		return addr + size;
	}

	void registerTlsSegments() {
		// TODO
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
int pthread_create(pthread_t* thread, pthread_attr_t* attr,
                   void* function(void*), void* arg);
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

void __sd_gc_set_stack_bottom(const void* bottom);
void __sd_gc_add_roots(const void[] range);
