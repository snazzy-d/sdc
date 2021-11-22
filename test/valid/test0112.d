//T compiles:yes
//T has-passed:yes
//T retval:42
// Test exclusion of invalid ref overloads.

int main() {
	return foo(0);
}

int foo(ref int i) {
	return 3;
}

int foo(long l) {
	return 42;
}
