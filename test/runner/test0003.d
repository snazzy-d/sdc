//T compiles:yes
//T retval:42
//T has-passed:yes
// Tests casting.

int main() {
	long a = 21; // int -> long, implicit
	int c = 21;
	if (a > c) {
		return 17;
	}

	return cast(int) a + c;
}
