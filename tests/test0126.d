//T compiles:yes
//T has-passed:yes
//T retval:25
// Test template argument deduction.

template Foo(T : U[], U) {
	// XXX: remove cast when VRP is in.
	enum Foo = cast(int) U.sizeof;
}

int main() {
	return Foo!(long[]) + Foo!string + Foo!(string[]);
}

