module dmd.thread;

extern(C):

// druntime API.
void thread_suspendAll();
void thread_resumeAll();

alias ScanAllThreadsFn = void delegate(void*, void*);
void thread_scanAll(ScanAllThreadsFn scan);

// sdrt API.
alias ScanFn = bool delegate(const(void*)[] range);
void __sd_thread_scan(ScanFn scan) {
	auto ts = ThreadScanner(scan);

	// FIXME: For some reason, this doesn't work
	// if the literal is passed directly.
	auto dg = ts.scanRange;
	thread_scanAll(dg);
}

void __sd_thread_stop_the_world() {
	thread_suspendAll();
}

void __sd_thread_restart_the_world() {
	thread_resumeAll();
}

private:

struct ThreadScanner {
	ScanFn scan;

	this(ScanFn scan) {
		this.scan = scan;
	}

	extern(C) void scanRange(void* start, void* stop) {
		import d.gc.range;
		scan(makeRange(start, stop));
	}
}
