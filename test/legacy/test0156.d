//T compiles:yes
//T has-passed:yes
//T retval:36
// Closure chaining

int main() {
	int a = 11;

	auto foo() {
		int b = 25;

		auto bar() {
			return a + b;
		}

		return bar;
	}

	return foo()();
}
