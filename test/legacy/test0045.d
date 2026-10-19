//T compiles:yes
//T has-passed:yes
//T retval:7

struct A {
	int A;

	int foo() {
		return A;
	}
}

int main() {
	A a;

	return a.foo() + 7;
}
