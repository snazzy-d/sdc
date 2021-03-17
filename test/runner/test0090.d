//T compiles:yes
//T has-passed:yes
//T retval:11

int main() {
	int b;

	for (int a = 1; a < 10; a--) {
		a += 4;
		b = a;
	}

	return b;
}
