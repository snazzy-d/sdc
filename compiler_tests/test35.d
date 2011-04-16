//T compiles:yes
//T retval:42

struct Foo
{
	int i;
}

struct Bar
{
    alias Foo Qux;
    
	static Qux baz()
	{
		Foo f;
		f.i = 42;
		return f;
	}
}

int main()
{
	return Bar.baz().i;
}

