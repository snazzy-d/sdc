//T compiles:yes
//T retval:42
//T has-passed:yes
// Tests ambiguous parsing.

int main() {
	T* function() f;
	T* delegate() dg;

	T* ptr;
	T** ptrptr;

	struct S {}
	S* foo() {
		return null;
	}

	S* foo(...) {
		return null;
	}

	S* foo(int a) {
		return null;
	}

	S* foo(int a, ...) {
		return null;
	}

	S* foo(S* s) {
		return s;
	}

	S* foo(S* s, ...) {
		return s;
	}

	// Expression * function T() { return 0; }
	// Expression * delegate T() { return 0; }

	return 42;
}

alias T = uint;
