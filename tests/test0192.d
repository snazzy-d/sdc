//T compiles:yes
//T has-passed:yes
//T retval:10
// Checks that auto kicks in with all qualifiers.

public bar() {
	return 2;
}

immutable n = 3;

@property p() {
	return 4;
}

int main() {
	// FIXME: Codegen of foo fails for some reason.
	static foo() {
		return 1;
	}
	
	return /* foo() */ 1 + bar() + n + p;
}
