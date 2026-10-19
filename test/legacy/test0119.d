//T compiles:no
//T has-passed:yes
// Test invalid override.

int main() {
	return 0;
}

class A {
	void foo(int a) {}
}

class B : A {
	override void bar(int a) {}
}
