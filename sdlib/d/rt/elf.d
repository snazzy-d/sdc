module d.rt.elf;

version(linux) {
	import core.stdc.pthread;

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

	void registerGlobalSegments() {
		import sys.linux.link;

		static extern(C)
		int __global_callback(dl_phdr_info* info, size_t size, void* data) {
			auto offset = info.dlpi_addr;

			auto segmentCount = info.dlpi_phnum;
			foreach (i; 0 .. segmentCount) {
				auto segment = info.dlpi_phdr[i];

				import sys.linux.elf;
				if (segment.p_type != PT_LOAD || !(segment.p_flags & PF_W)) {
					continue;
				}

				import d.gc.capi;
				auto start = cast(void*) (segment.p_vaddr + offset);
				__sd_gc_add_roots(start[0 .. segment.p_memsz]);
			}

			return 0;
		}

		dl_iterate_phdr(__global_callback, null);
	}

	void registerTlsSegments() {
		import sys.linux.link;

		static extern(C)
		int __tls_callback(dl_phdr_info* info, size_t size, void* data) {
			auto tlsStart = info.dlpi_tls_data;
			if (tlsStart is null) {
				// FIXME: make sure this is not lazy initialized or something.
				return 0;
			}

			auto segmentCount = info.dlpi_phnum;
			foreach (i; 0 .. segmentCount) {
				auto segment = info.dlpi_phdr[i];

				import sys.linux.elf;
				if (segment.p_type != PT_TLS) {
					continue;
				}

				import d.gc.capi;
				__sd_gc_add_tls_segment(tlsStart[0 .. segment.p_memsz]);
			}

			return 0;
		}

		dl_iterate_phdr(__tls_callback, null);
	}
}

version(OSX) {
	import core.stdc.pthread;

	void* getStackBottom() {
		return pthread_get_stackaddr_np(pthread_self());
	}

	extern(C) void _d_dyld_registerTLSRange();

	void registerTlsSegments() {
		_d_dyld_registerTLSRange();
	}
}

version(FreeBSD) {
	import core.stdc.pthread;

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
