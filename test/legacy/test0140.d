//T compiles:yes
//T has-passed:yes
//T retval:35
// Scope exit.

int a = 10;

int foo() {
	a++;
	scope(exit) a *= 2;

	return a++;
}

int main() {
	return foo() + a;
}
