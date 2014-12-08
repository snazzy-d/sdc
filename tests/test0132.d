//T compiles:yes
//T has-passed:yes
//T retval:42
// Test IFTI with partial instanciation.

auto foo(T, U)(T t, U u) {
	// XXX: Remove cast when we can get VRP
	return cast(int)  (t + T.sizeof + u + U.sizeof);
}

int main() {
	return foo!long('A', -35);
}

