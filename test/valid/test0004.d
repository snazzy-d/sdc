//T compiles:yes
//T retval:12
//T has-passed:yes
// Tests the casting of booleans to ints.

int main() {
	bool a = false, b = true;
	if (cast(int) a != 0) {
		return 1;
	}

	if (cast(int) b != 1) {
		return 2;
	}

	a = true;
	return a + b + 10;
}
