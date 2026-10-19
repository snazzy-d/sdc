//T compiles:yes
//T has-passed:yes
//T retval:42
// Closure chaining

int main() {
	int a = 9;

	auto foo() {
		int b = 11;

		auto bar() {
			return a++ + b++;
		}

		return bar() + b;
	}

	return foo() + a;
}
