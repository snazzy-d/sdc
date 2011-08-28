//T compiles:yes
//T has-passed:no
//T retval:41

auto add(int a, int b)
{
    return a + b;
}

int main()
{
    return add(20, 21);
}

