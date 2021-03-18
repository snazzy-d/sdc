//T compiles:no
//T has-passed:yes
// Goto over initialization.

int main() {
	if (false) {
		int i;

	OverInit:
	}

	goto OverInit;
}
