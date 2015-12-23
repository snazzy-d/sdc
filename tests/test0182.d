//T compiles:yes
//T has-passed:yes
//T retval:42
// this + context.

struct Foo {
	uint a = 13;
	
	// FIXME: handle implicitly defined constructors.
	this() {}
	
	uint bar(alias fun)() {
		return fun(buzz()) + buzz();
	}
	
	uint buzz() {
		return a++;
	}
}

int main() {
	uint b = 7;
	uint foo(uint a) {
		return a + b++;
	}
	
	auto f = Foo();
	return f.bar!foo() + b;
}
