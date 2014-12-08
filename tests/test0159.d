//T compiles:yes
//T has-passed:yes
//T retval:25
// template typed alias parameter (value)

auto foo(alias T U, T)() {
	// XXX: remove cast when VRP is in.
	return cast(int) (U + T.sizeof);
}

int main() {
	return foo!true() + foo!10() + foo!I();
}

enum I = 5;

