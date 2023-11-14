module d.rt.contract;

extern(C):

void __sd_assert_fail(string file, int line) {
	import core.stdc.stdlib, core.stdc.stdio;
	snprintf(_dbgPrintBuffer.ptr, DbgPrintBufferSize, "assert fail: %s:%d\n",
	         file.ptr, line);
	printDebug();
	exit(1);
}

void __sd_assert_fail_msg(string msg, string file, int line) {
	import core.stdc.stdlib, core.stdc.stdio;
	snprintf(_dbgPrintBuffer.ptr, DbgPrintBufferSize, "%s: %s:%d\n", msg.ptr,
	         file.ptr, line);
	printDebug();
	exit(1);
}
