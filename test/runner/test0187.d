//T compiles:no
//T has-passed:yes
// Tests missing default in non-final switches

int main() {
	int x = 10;
	switch (x) {
		case 0:
			return 1;

		case 2:
			return 2;
	}
}
