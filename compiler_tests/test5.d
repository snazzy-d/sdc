//T compiles:yes
//T retval:42
// Tests simple functions, and use before definition.

int main()
{
    return add(21, add(20, 1));
}

int add(int a, int b)
{
    return a + b;
}
