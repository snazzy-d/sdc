/// Part of a 'mock' phobos used for testing. Not intended for real use.
module std.stdio;

void writeln(string s) {
	import core.stdc.stdio;
	printf("%.*s\n", s.length, s.ptr);
}

void writeln(int i) {
	import core.stdc.stdio;
	printf("%d\n", i);
}
