//T compiles:yes
//T has-passed:yes
//T retval:42
// Test multiple argument IFTI.

auto foo(T, U)(T t, U u) {
	return t + T.sizeof + u + U.sizeof;
}

int main() {
	return cast(int) foo('A', -28);
}
