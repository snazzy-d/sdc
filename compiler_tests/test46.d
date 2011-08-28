//T compiles:yes
//T retval:13
//T known:yes

class Test
{
    int i;

    this()
    {
        i = 12;
    }

    int foo()
    {
        return i + 1;
    }
}

int main()
{
    auto test = new Test();
    return test.foo();
}

