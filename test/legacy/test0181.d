//T compiles:yes
//T has-passed:yes
//T retval:3
// dtor.

struct Foo {
	uint* a;

	this(ref uint a) {
		this.a = &a;
	}

	~this() {
		*a = 2 * *a;
	}
}

struct Bar {
	Foo f;

	this(ref uint a) {
		f = Foo(a);
	}

	~this() {
		auto a = f.a;
		*a = 2 * *a + 1;
	}
}

int main() {
	uint a = 3;
	return a;
}
