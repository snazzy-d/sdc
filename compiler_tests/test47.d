//T compiles:yes
//T retval:27

int add(int a, int b)
{
    return a + b;
}

int add(int a, int b, int c)
{
    return a + b + c;
}

float add(float a, float b)
{
    return a + b;
}

float add(float a, float b, int c)
{
    return a + b + c;
}

int main()
{
    return add(5, cast(int) add(3.2, 6.4)) + cast(int) add(3.0, 3.0, add(1, 2, 4));
}

