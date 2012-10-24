//T compiles:yes
//T retval:42

alias Fizz Buzz;

struct Bar
{
	static auto baz()
	{
		Qux f;
		f.i = 42;
		return f;
	}
	
	alias Baz Qux;
}

alias Foo Baz;

struct Foo
{
	Buzz i;
}

alias int Fizz;

int main()
{
	return Bar.baz().i;
}
