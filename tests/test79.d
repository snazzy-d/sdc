//T compiles:yes
//T retval:0

int main()
{
    int a;
    auto b = &a;
    auto c = b;
    assert(b == c);
    return 0;
}

