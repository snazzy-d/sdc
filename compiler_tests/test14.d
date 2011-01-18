//T compiles:yes
//T retval:58

int foo(int a)
{
    int a = 56;
    if (a == 56 || a++) {
        a++;
    }
    if (a != 57 && a--) {
        a = 32;
    }
    if (a == 57 && a++) {
    }
    return a;
}

int main()
{
    return foo(56);
}
