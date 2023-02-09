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

int bar(bool cond) {
	uint x = 13;

	if (cond) {
		scope(exit) x *= 2;
		x = 15;
	}

	return x;
}

int main() {
	assert(bar(false) == 13);
	assert(bar(true) == 30);

	return foo(true) + foo(false) + a;
}
