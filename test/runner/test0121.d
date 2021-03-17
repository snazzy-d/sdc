//T compiles:yes
//T has-passed:yes
//T retval:42
// Test virtual dispatch.

int main() {
	A a = new B();
	return a.foo();
}

class A {
	int a = 15;

	int foo() {
		return a;
	}
}

class B : A {
	int b = 27;

	override int foo() {
		return a + b;
	}
}
