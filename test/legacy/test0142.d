//T compiles:yes
//T has-passed:yes
//T retval:42
// Scope exit with nested blocks.

int a = 10;

int foo() {
	scope(exit) a = 11;

	{
		auto b = a;
		scope(exit) a = a * 3 + b;

		a = 7;
	}

	return a;
}

int main() {
	return foo() + a;
}
