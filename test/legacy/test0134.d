//T compiles:no
//T has-passed:yes
// Forbiden method name.

struct Foo {
	void __dtor() {}
}

void main() {}
