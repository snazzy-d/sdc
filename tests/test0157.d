//T compiles:yes
//T has-passed:yes
//T retval:25
// template alias parameter (value)

auto foo(alias U)() {
	// XXX: remove cast when VRP is in.
	return cast(int) (U + typeof(U).sizeof);
}

int main() {
	return foo!true() + foo!10() + foo!I();
}

enum I = 5;

