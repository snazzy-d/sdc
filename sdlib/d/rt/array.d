module d.rt.array;

extern(C):

void __sd_array_outofbounds(string file, int line) {
	import core.stdc.stdlib, core.stdc.stdio;
	printf("bound check fail: %s:%d\n", file.ptr, line);
	exit(1);
}
