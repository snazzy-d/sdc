//T compiles:yes
//T has-passed:yes
//T retval:18

int main() {
	int a = 19;

	do {
		a--;
	} while (a > 20);

	return a;
}
