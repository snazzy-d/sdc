module d.rt.contract;

extern(C):

void __sd_assert_fail(string file, int line) {
	import core.stdc.stdlib, core.stdc.stdio;
	printf("assert fail: %s:%d\n".ptr, file.ptr, line);
	exit(1);
}

void __sd_assert_fail_msg(string msg, string file, int line) {
	import core.stdc.stdlib, core.stdc.stdio;
	printf("%s: %s:%d\n".ptr, msg.ptr, file.ptr, line);
	exit(1);
}
