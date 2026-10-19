//T compiles:yes
//T has-passed:yes
//T retval:42

struct Foo {
	int i;
}

struct Bar {
	static Qux baz() {
		Foo f;
		f.i = 42;

		return f;
	}

	alias Qux = Foo;
}

int main() {
	return Bar.baz().i;
}
