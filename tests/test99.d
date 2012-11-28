//T compiles:yes
//T retval:12

struct Fizz {
	Qux!Bar buzz;
	
	auto get7() {
		return buzz.baz + 2;
	}
}

template Foo(T) {
    T Foo;
}

struct Bar {
	Qux!int baz = 5;
}

template Qux(T) {
	alias T Qux;
}

int main() {
    return Foo!Bar.baz + Foo!Fizz.get7();
}

