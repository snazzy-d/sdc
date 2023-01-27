//T compiles:yes
//T has-passed:yes
//T retval:4

class Foo {
	void func1() {}

	void func2() do {}

	void func3() in {} do {}

	void func4() out {} do {}

	void func5() out {} in {} do {}

	void func6() in {} out {} do {}
}

void func1() {}

void func2() do {}

void func3() in {} do {}

void func4() out {} do {}

void func5() out {} in {} do {}

void func6() in {} out {} do {}

int main() {
	return 4;
}
