//T compiles:yes
//T has-passed:yes
//T retval:42

int main() {
	return foo(42);
}

string foo() {
	return bar();
}

mixin(bar());

string bar() {
	return "int foo(int i) { return i; }";
}
