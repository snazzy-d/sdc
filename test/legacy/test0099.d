//T compiles:yes
//T has-passed:yes
//T retval:12

int main() {
	return Foo!Bar.baz + Fizz!Buzz.get7();
}

template Foo(T) {
	T Foo;
}

alias Fizz = Foo;

struct S {
	Qux!Bar buzz;

	auto get7() {
		return buzz.baz + 2;
	}
}

alias Buzz = S;

struct Bar {
	Qux!int baz = 5;
}

template Qux(T) {
	alias Qux = T;
}
