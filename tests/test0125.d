//T compiles:yes
//T has-passed:yes
//T retval:9
// Test template specialisation.

template Foo(T : T*) {
	// XXX: remove cast when VRP is in.
	enum Foo = cast(int) T.sizeof;
}

int main() {
	return Foo!(char*) + Foo!(long*);
}

