//T compiles:yes
//T has-passed:yes
//T retval:42

int main() {
	int a = 42;
	int b = 0;

	while (a > 0) {
		a--;
		b++;
	}

	return b;
}
