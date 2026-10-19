//T compiles:yes
//T has-passed:yes
//T retval:9
// Test template specialisation.

template Foo(T : T*) {
	enum Foo = T.sizeof;
}

int main() {
	return Foo!(char*) + Foo!(long*);
}
