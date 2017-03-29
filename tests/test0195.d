//T compiles:yes
//T has-passed:yes
// unitest blocks.

unittest {}

unittest foo {
	printf("foo \\o/\n".ptr);
}

unittest bar {
	assert(0, "bar do not pass");
}

void main() {}
