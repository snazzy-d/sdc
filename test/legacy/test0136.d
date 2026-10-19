//T compiles:yes
//T has-passed:yes
//T retval:42
// Method overload.

struct Foo {
	int i;

	this(int i) {
		this.i = i;
	}

	auto bar(int j) {
		return i + j;
	}

	int bar() {
		return bar(-5);
	}
}

int main() {
	auto f = Foo(47);
	return f.bar();
}
