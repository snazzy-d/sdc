//T compiles:yes
//T has-passed:yes
//T retval:138
// extern(C) variable and function.

extern(C) int bar = 138;

extern(C) int foo() {
	return bar;
}

int main() {
	return foo();
}
