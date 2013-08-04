//T compiles:yes
//T retval:42
//T has-passed:yes

int foo() {
	return 42;
}

int main() {
	void* p = &foo;
	auto fn = (cast(int function())p)();
	return fn;
}

