//T compiles:yes
//T has-passed:yes
//T retval:42
// Test virtual dispatch.

int main() {
	A a = new A();
	return a.foo();
}

class A {
	int foo() {
		return 42;
	}
}
