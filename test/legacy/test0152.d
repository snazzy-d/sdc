//T compiles:yes
//T has-passed:yes
//T retval:36
// Closure

int main() {
	int a = 10;
	int fooa() {
		return --a;
	}

	int b = 5;
	int foob() {
		return --a + b++;
	}

	return fooa() + foob() + a++ + b--;
}
