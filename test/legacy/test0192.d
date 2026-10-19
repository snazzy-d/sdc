//T compiles:yes
//T has-passed:yes
//T retval:10
// Checks that auto kicks in with all qualifiers.

public bar() {
	return 2;
}

immutable n = 3;

@property
	p() {
	return 4;
}

int main() {
	static foo() {
		return 1;
	}

	return foo() + bar() + n + p;
}
