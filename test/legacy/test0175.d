//T compiles:yes
//T retval:42
//T has-passed:yes
// ref return.

int a;

ref int foo() {
	return a;
}

int main() {
	foo() = 42;
	return a;
}
