//T compiles:yes
//T has-passed:yes
//T retval:42
// Test IFTI with partial instanciation.

auto foo(T, U)(T t, U u) {
	return t + T.sizeof + u + U.sizeof;
}

int main() {
	return cast(int) foo!long('A', -35);
}
