//T compiles:yes
//T has-passed:yes
//T retval:40
// template value parameter

int vpT(int I)() {
        return I;
}

auto foo(T U, T)() {
	return cast(int) (U + T.sizeof);
}

int main() {
	return foo!true() + foo!10() + 
		foo!I() + vpT!10() + vpT!I();
}

enum I = 5;

