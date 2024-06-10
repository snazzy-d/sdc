//T error: while_unreachable.d:13:1:
//T error: This statement is unreachable.

bool doTheThing();

int main() {
	while (true) {
		if (doTheThing()) {
			return 0;
		}
	}

	return 7;
}
