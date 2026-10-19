//T compiles:yes
//T has-passed:yes
//T retval:42
// this passed down via context.

class Foo {
	uint a = 13;

	uint bar() {
		auto dg = {
			return buzz();
		};

		return dg() + buzz() + a;
	}

	uint buzz() {
		return a++;
	}
}

int main() {
	return new Foo().bar();
}
