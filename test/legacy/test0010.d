//T compiles:yes
//T retval:12
//T has-passed:yes
// Tests typeof and evaluation of expressions with no side-effects.

int main() {
	int i = 12;
	typeof(i++) j;

	return i + j;
}
