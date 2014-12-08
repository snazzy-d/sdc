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
	// XXX: remove cast when VRP is in.
	return cast(int) (Foo!(int*) + Foo!(long[]) + Foo!char);
}

