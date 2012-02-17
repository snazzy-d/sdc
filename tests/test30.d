//T compiles:yes
//T retval:42
//T has-passed:no

enum {
	A = 42,
	B = A
}

int main()
{
	return B;
}

