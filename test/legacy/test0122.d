//T compiles:yes
//T has-passed:yes
//T retval:58

int bar(int n) {
	switch (n) {
		case 0:
			return -9; // Bad case !

		case 25:
			return 75;

		case 42:
			return 69;

		case 666:
			return 999;

		default:
			return -1;
	}
}

int foo(int n) {
	if (n == 0) {
		return bar(n);
	}

	switch (n) {
		case 1:
			return 23;

		case 2:
		case 3:
			return n;

		default:
			return bar(n);
	}
}

int main() {
	return foo(0) + foo(42) - foo(2);
}
