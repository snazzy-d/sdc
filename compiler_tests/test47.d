//T compiles:yes
//T retval:28
//T known:yes

int add(int a, int b)
{
    return a + b;
}

int add(int a, int b, int c)
{
    return a + b + c;
}

int main()
{
    return add(20, add(5, 2, 1));
}

