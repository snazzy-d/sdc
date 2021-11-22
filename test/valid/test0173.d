//T compiles:no
//T has-passed:yes
// Unreachable statement

int main() {
	int i = 5;
	if (i) {
		return 3;
	} else {
		return 5;
	}

	return 7;
}
