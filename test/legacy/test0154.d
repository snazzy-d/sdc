//T compiles:yes
//T has-passed:yes
//T retval:42
// template value parameter

auto foo(T U, T)() {
	return cast(int) (U + T.sizeof);
}

auto bar(uint I)() {
	return I;
}

int main() {
	return foo!true() + foo!10() + foo!I() + bar!12() + bar!I();
}

enum I = 5;
