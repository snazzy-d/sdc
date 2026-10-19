//T compiles:no
//T has-passed:yes
// Test ref overloads.

int main() {
	int i, j;
	return foo(i, j);
}

int foo(ref int i, int j) {
	return 0;
}

int foo(int i, ref int j) {
	return 0;
}
