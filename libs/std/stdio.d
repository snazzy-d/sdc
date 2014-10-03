/// Part of a 'mock' phobos used for testing. Not intended for real use.
module std.stdio;
void writeln(string s) {
	printf("%.*s\n".ptr, s.length, s.ptr);
}

void writeln(int i) {
	printf("%d\n".ptr, i);
}
