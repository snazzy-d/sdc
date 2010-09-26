//T compiles:yes
//T retval:42
// Tests simple functions.

int add(int a, int b)
{
    return a + b;
}

int main()
{
    return add(21, add(20, 1));
}
