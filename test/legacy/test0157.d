//T compiles:yes
//T has-passed:yes
//T retval:25
// template alias parameter (value)

int foo(alias U)() {
	return U + typeof(U).sizeof;
}

int main() {
	return foo!true() + foo!10() + foo!I();
}

enum I = 5;
