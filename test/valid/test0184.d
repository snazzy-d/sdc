//T compiles:no
//T has-passed:yes
// Tests multiple default in non-final switches

int main() {
	int x = 10;
	switch (x) {
		case 0:
			return 1;

		case 2:
			return 2;

		default:
			return 5;

		default:
			return 7;
	}
}
