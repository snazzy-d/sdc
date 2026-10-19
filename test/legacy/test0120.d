//T compiles:no
//T has-passed:yes
// Test implicit override error.

int main() {
	return 0;
}

class A {
	void foo(int a) {}
}

class B : A {
	void foo(int a) {}
}
