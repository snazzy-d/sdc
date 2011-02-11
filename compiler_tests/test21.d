//T compiles:yes
//T retval:42

int foo() { return 42; }
int main()
{
	int function()[] l;
	l.length = 1;
	l[0] = &foo;
	auto b = l[0];  // Workaround parser bug for now.
	return b();
}

