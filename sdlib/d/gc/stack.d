module d.gc.stack;

import d.gc.types;

version(OSX) {
	// For some reason OSX's symbol get a _ prepended.
	extern(C) void _sd_gc_push_registers(void delegate());
	alias __sd_gc_push_registers = _sd_gc_push_registers;
} else {
	extern(C) void __sd_gc_push_registers(void delegate());
}

void scanStack(ScanDg scan) {
	auto ts = ThreadScanner(scan);
	__sd_gc_push_registers(ts.scanStack);
}

private:

struct ThreadScanner {
	ScanDg scan;

	this(ScanDg scan) {
		this.scan = scan;
	}

	void scanStack() {
		import sdc.intrinsics;
		auto top = readFramePointer();

		import d.gc.tcache;
		auto bottom = threadCache.stackBottom;

		import d.gc.range;
		scan(makeRange(top, bottom));
	}
}
