//T compiles:yes
//T has-passed:yes
//T retval:25
// Test template argument deduction.

template Foo(T : U[], U) {
	enum Foo = U.sizeof;
}

int main() {
	uint a = 0;
	static if (size_t.sizeof==uint.sizeof) {
 		a = 8; 
	}
	return Foo!(long[]) + Foo!string + Foo!(string[]) + a;
}

