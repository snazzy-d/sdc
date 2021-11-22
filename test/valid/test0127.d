//T compiles:yes
//T has-passed:yes
//T retval:13
// Test template overload on specialisation.

template Foo(T) {
	enum Foo = T.sizeof;
}

template Foo(T : T*) {
	enum Foo = T.sizeof;
}

template Foo(T : T[]) {
	enum Foo = T.sizeof;
}

int main() {
	return Foo!(int*) + Foo!(long[]) + Foo!char;
}
