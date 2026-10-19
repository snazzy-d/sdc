//T compiles:no
//T has-passed:yes
// Must use goto case

void main() {
	switch (0) {
		case 0:
			int i;
		case 1:
		default:
	}
}
