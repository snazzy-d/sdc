//T error: unreachable.d:12:1:
//T error: This statement is unreachable.

int main() {
	int i = 5;
	if (i) {
		return 3;
	} else {
		return 5;
	}

	return 7;
}
