//T compiles:yes
//T has-passed:yes
//T retval:24
// Test closure with no capture.

int main() {
	struct S {
		int foo() {
			return 11;
		}
	}

	auto bar() {
		return 13;
	}

	S s;
	return s.foo() + bar();
}
