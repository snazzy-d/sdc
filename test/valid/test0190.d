//T compiles:yes
//T has-passed:yes
//T retval:35
// Scope success.

int a = 10;

int foo() {
	a++;
	scope(success) a *= 2;

	return a++;
}

int main() {
	return foo() + a;
}
