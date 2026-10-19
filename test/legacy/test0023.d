//T compiles:yes
//T has-passed:yes
//T retval:42

int foo() {
	return 42;
}

int main() {
	void* p = &foo;
	auto fn = (cast(int function()) p)();

	return fn;
}
