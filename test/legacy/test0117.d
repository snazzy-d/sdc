//T compiles:no
//T has-passed:yes
// Test invalid override.

int main() {
	return 0;
}

class A {
	int foo() {
		return 3;
	}
}

class B : A {
	override long foo() {
		return 7;
	}
}
