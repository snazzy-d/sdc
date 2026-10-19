//T compiles:yes
//T has-passed:yes
//T retval:42
// alias parameters with context.

auto forward(alias fun)() {
	return fun();
}

int main() {
	int a = 42;
	auto foo() {
		return a;
	}

	auto bar() {
		return forward!foo();
	}

	return bar();
}
