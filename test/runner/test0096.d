//T compiles:yes
//T has-passed:yes
//T retval:12

template Foo(T) {
	T Foo;
}

int main() {
	Foo!int = 4;
	Foo!long = 2 * Foo!int;

	Foo!int = 4 + cast(typeof(Foo!int)) (Foo!long + Foo!bool);

	return Foo!int;
}
