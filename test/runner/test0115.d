//T compiles:yes
//T has-passed:yes
//T retval:17
// Test overloads priority.

int main() {
	int i, j;
	return foo(i, j);
}

int foo(long i, long j) {
	return 23;
}

int foo(long i, int j) {
	return 17;
}
