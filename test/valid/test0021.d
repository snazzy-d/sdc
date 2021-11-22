//T compiles:yes
//T has-passed:no
//T retval:42

int foo() {
	return 42;
}

int main() {
	int function()[] l;
	l.length = 1;
	l[0] = &foo;

	return l[0]();
}
