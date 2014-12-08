//T compiles:yes
//T has-passed:yes
//T retval:25
// template value parameter

auto foo(T U, T)() {
	// XXX: remove cast when VRP is in.
	return cast(int) (U + T.sizeof);
}

int main() {
	return foo!true() + foo!10() + foo!I();
}

enum I = 5;

