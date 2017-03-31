//T compiles:yes
//T has-passed:yes
// unitest blocks.

unittest {}

unittest foo {
	import core.stdc.stdio;
	printf("foo \\o/\n".ptr);
}

unittest bar {
	static fail() {
		throw new Exception();
	}
	
	fail();
}

void main() {}
