//T compiles:yes
//T has-passed:yes
//T retval:43
// Scope exit with conditional blocks.

int a = 9;

int foo(bool fi) {
	scope(exit) a = 11;

	auto b = a;
	if (fi) {
		a = 7;
		return a + b;
	}

	a = 5;
	return a + b;
}

int main() {
	return foo(true) + foo(false) + a;
}
