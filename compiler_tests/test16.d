//T compiles:yes
//T retval:32

int foo()
{
    return 32;
}

int main()
{
    int function() f;
    f = &foo;
    return f();
}
