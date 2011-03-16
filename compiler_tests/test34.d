//T compiles:yes
//T retval:17

struct S
{
	A foo(bar b)
	{
		A a;
		a.i = b;
		return a;
	}
}

struct A
{
	int i;
}

alias int bar;


int main()
{
	S s;
	return s.foo(16).i + 1;
}

