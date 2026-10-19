//T compiles:yes
//T has-passed:yes
//T retval:42
// Constructor forwarding.

class Foo {
	int i;
	int j;

	this(int i) {
		this(i, 31);
	}

	this(int i, int j) {
		this.i = i;
		this.j = j;
	}

	auto bar() {
		return i + j;
	}
}

int main() {
	auto f = new Foo(11);
	return f.bar();
}
