//T compiles:yes
//T has-passed:yes
//T retval:58

int foo(int n) {
	if (n == 17) {
		return 16;
	} else if (n == 16) {
		return 32;
	} else {
		if (n == 0) {
			return 16;
		} else if (n == 17) {
			return 8;
		} else {
			return 7;
		}
	}
}

int main() {
	return foo(0) + 42;
}
