//T compiles:yes
//T has-passed:yes
//T retval:42

int main() {
	int a = 42;
	int b = -14;

	while (a) {
		a--;

		if (a % 3) {
			b += 2;
		}
	}

	return b;
}
