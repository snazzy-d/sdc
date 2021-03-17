//T compiles:no
//T has-passed:yes

int main() {
	return foo();
}

int foo() {
	return 3;
}

static if (foo() == 3) {
	int foo(int i) {
		return i;
	}
}
