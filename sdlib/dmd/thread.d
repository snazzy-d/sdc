module dmd.thread;

extern(C):

// druntime API.
void thread_suspendAll();
void thread_resumeAll();

// note, we must interface with DMD using extern(C) calls, so we
// cannot call thread_scanAll directly. This requires a hook compiled
// on the druntime side that forwards to thread_scanAll, and we cannot
// use delegates (as those are not the same ABI)
// the context pointer is the SDC-defined object that will run the scan
// (ThreadScanner).
void __sd_scanAllThreadsFn(void* start, void* end, void* context) {
	// cast the context to a pointer to a ThreadScanner
	(cast(ThreadScanner*) context).scanRange(start, end);
}

//alias ScanAllThreadsFn = void delegate(void*, void*);
//void thread_scanAll(ScanAllThreadsFn scan);

// defined in druntime. The context pointer gets passed to the scan routine
void __sd_thread_scanAll(typeof(&__sd_scanAllThreadsFn) scan, void* context);

// sdrt API.
alias ScanFn = bool delegate(const(void*)[] range);
void __sd_thread_scan(ScanFn scan) {
	auto ts = ThreadScanner(scan);

	// FIXME: For some reason, this doesn't work
	// if the literal is passed directly.
	//auto dg = ts.scanRange;
	__sd_thread_scanAll(&__sd_scanAllThreadsFn, &ts);
}

void __sd_thread_stop_the_world() {
	thread_suspendAll();
}

void __sd_thread_restart_the_world() {
	thread_resumeAll();
}

void __sd_thread_create() {
	import d.gc.capi;
	__sd_gc_init();
}

void __sd_thread_destroy() {}

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
