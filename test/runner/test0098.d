//T compiles:yes
//T has-passed:yes
//T retval:42

alias Buzz = Fizz;

struct Bar {
	static auto baz() {
		Qux f;
		f.i = 42;
		return f;
	}

	alias Qux = Baz;
}

alias Baz = Foo;

struct Foo {
	Buzz i;
}

alias Fizz = int;

int main() {
	return Bar.baz().i;
}
