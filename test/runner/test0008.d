//T compiles:yes
//T retval:42
//T has-passed:yes
// Tests increment/decrement semantics.

int add(int a, int b) {
	return a + b;
}

int main() {
	int a = 40;
	int b = 3;

	return add(a++, --b);
}
