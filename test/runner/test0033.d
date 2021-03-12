//T compiles:yes
//T has-passed:yes
//T retval:25

struct S {
	static int foo() {
		return 21;
	}

	int bar() {
		return 4;
	}
}

int main() {
	S s;

	return S.foo() + s.bar();
}
