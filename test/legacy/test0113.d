//T compiles:yes
//T has-passed:yes
//T retval:42
// Test ref overloads.

int main() {
	int i = -1;
	return foo(i) + foo(30);
}

int foo(ref int i) {
	return i + 3;
}

int foo(int i) {
	return i + 10;
}
