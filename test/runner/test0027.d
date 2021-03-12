//T compiles:yes
//T has-passed:yes
//T retval:1

enum Foo {
	Bar,
	Baz,
}

int main() {
	return Foo.Baz;
}
