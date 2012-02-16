//T compiles:no

void foo(ref long i)
{
    i = 42;
}

int main()
{
    int i;
    foo(i);
    return i;
}

