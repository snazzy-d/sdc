//T compiles:no
//T has-passed:yes
// Goto over initialization.

int main() {
	goto OverInit;
	int i;

OverInit:
}
