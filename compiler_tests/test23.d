//T compiles:yes
//T retval:42

int foo()
{
	return 42;
}

int main()
{
	void* p = cast(void*) &foo;  // Workaround parser bug for now.
	auto fn = cast(int function()) p;  // This should be casted and called directly.
	return fn();
}

