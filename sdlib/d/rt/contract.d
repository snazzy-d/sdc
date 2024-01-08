module d.rt.contract;

enum DbgPrintBufferSize = 4096;

static char[DbgPrintBufferSize] _dbgPrintBuffer;

extern(C):

void __sd_print_debug_message(string file, int line, string message) {
	import core.stdc.unistd, core.stdc.stdio;
	auto len =
		snprintf(_dbgPrintBuffer.ptr, DbgPrintBufferSize, "%.*s:%d: %.*s\n",
		         file.length, file.ptr, line, message.length, message.ptr);
	write(STDERR_FILENO, _dbgPrintBuffer.ptr, len);
}

void __sd_assert_fail(string file, int line) {
	__sd_print_debug_message(file, line, "assert failure.");

	import core.stdc.stdlib;
	exit(1);
}

void __sd_assert_fail_msg(string msg, string file, int line) {
	__sd_print_debug_message(file, line, msg);

	import core.stdc.stdlib;
	exit(1);
}
