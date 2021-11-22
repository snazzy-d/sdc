//T compiles:yes
//T has-passed:yes
//T retval:18
// Scope exit that returns.

int a = 10;

int foo() {
	scope(exit) a = 7;
	scope(exit) return a;

	return a++;
}

int main() {
	return foo() + a;
}
