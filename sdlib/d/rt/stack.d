import d.rt.stack;

extern(C):
version(OSX) {
	// For some reason OSX's symbol get a _ prepended.
	void _sd_gc_push_registers(void delegate());
	alias __sd_gc_push_registers = _sd_gc_push_registers;
} else {
	void __sd_gc_push_registers(void delegate());
}
