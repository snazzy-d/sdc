module d.thread;

import core.stdc.pthread;

extern(C) void __sd_thread_init() {
	import d.gc.tcache, d.gc.emap, d.gc.base;
	threadCache.initialize(&gExtentMap, &gBase);

	registerTlsSegments();
}

alias ScanDg = bool delegate(const(void*)[] range);
extern(C) void __sd_thread_scan(ScanDg scan) {
	auto ts = ThreadScanner(scan);

	import d.rt.stack;
	__sd_gc_push_registers(ts.scanStack);
}

extern(C) void __sd_thread_stop_the_world() {
	// TODO: Actually stop the world.
}

extern(C) void __sd_thread_restart_the_world() {
	// TODO: Actually stop the world.
}

private:

struct ThreadScanner {
	ScanDg scan;

	this(ScanDg scan) {
		this.scan = scan;
	}

	bool scanStack() {
		import sdc.intrinsics;
		auto top = readFramePointer();
		auto bottom = getStackBottom();

		import d.gc.range;
		return scan(makeRange(top, bottom));
	}
}

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

		auto segmentCount = info.dlpi_phnum;
		foreach (i; 0 .. segmentCount) {
			auto segment = info.dlpi_phdr[i];

			import sys.linux.elf;
			if (segment.p_type != PT_TLS) {
				continue;
			}

			import d.gc.capi;
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
