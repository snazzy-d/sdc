//T compiles:yes
//T retval:42

struct Foo
{
	int i;
}

struct Bar
{
	static Qux baz()
	{
		Foo f;
		f.i = 42;
		return f;
	}

	alias Foo Qux;
}

int main()
{
	return Bar.baz().i;
}

