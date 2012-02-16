//T compiles:yes
//T retval:32

int add(int a, int b)
{
    return a + b;
}

int main()
{
    int function(int, int) f;
    f = &add;
    return f(30, 2);
}
