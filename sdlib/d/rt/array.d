module d.rt.array;

extern(C):

void __sd_array_outofbounds(string file, int line) {
	import d.rt.contract;
	__sd_assert_fail_msg("bound check fail.", file, line);
}
