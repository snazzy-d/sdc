//T compiles:yes
//T retval:84
//T has-passed:yes
// Tests local variables with simple expressions.

int main() {
	int a = 42, b = 21;
	int c = 2;
	return a + b * c;
}
