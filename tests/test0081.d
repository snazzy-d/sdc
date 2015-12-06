//T compiles:yes
//T has-passed:yes
//T retval:35
// UFCS and getter @property

@property
int triple(int a) {
	return a * 3;
}

int foo() @property {
	return 2;
}

int main() {
	int a = 11;
	return a.triple + foo;
}
