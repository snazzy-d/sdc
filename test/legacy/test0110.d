//T compiles:yes
//T has-passed:yes
//T retval:42
// Test recurence.

int main() {
	return fact(4) + fact(5) / fact(3) - fact(2);
}

int fact(int n) {
	if (n < 2) {
		return 1;
	}

	return n * fact(n - 1);
}
