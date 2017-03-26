module d.rt.array;

extern(C):

void __sd_array_outofbounds(string file, int line) {
	printf("bound check fail: %s:%d\n".ptr, file.ptr, line);
	exit(1);
}
