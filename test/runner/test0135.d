//T compiles:yes
//T has-passed:yes
//T retval:42
// Constructor.

struct Foo {
	int i;

	this(int i) {
		this.i = i;
	}

	auto bar() {
		return i;
	}
}

int main() {
	auto f = Foo(42);
	return f.bar();
}
