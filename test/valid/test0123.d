//T compiles:yes
//T has-passed:yes
//T retval:42
// Test forward reference in enums.

enum Foo {
	Fizz,
	Pion,
	Bar = Baz + Pion,
	Baz = Buzz - Fizz,
	Qux = 40,
	Buzz,
}

int main() {
	return Foo.Bar;
}
