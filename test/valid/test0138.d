//T compiles:yes
//T has-passed:yes
//T retval:42
// Newing structs.

struct Foo {
	int i;
	int j;

	this(int i, int j) {
		this.i = i;
		this.j = j;
	}

	auto bar(int k) {
		return i + j + k;
	}
}

int main() {
	auto f = new Foo(12, 35);
	return f.bar(-5);
}
