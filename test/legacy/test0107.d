//T compiles:no
//T has-passed:yes

int main() {
	return 42;
}

string foo() {
	return "int foo(int i) { return i; }";
}

mixin(foo());
