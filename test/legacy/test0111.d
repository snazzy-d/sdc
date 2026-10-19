//T compiles:yes
//T has-passed:yes
//T retval:0
// Test function overloads.

int main() {
	byte b;
	short s;
	int i;
	long l;

	assert(foo(b) == 1);
	assert(foo(s) == 2);
	assert(foo(i) == 3);
	assert(foo(42) == 3);
	assert(foo(l) == 4);

	return 0;
}

int foo(byte b) {
	return 1;
}

int foo(short s) {
	return 2;
}

int foo(int i) {
	return 3;
}

int foo(long l) {
	return 4;
}
