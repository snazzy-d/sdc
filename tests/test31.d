//T compiles:yes
//T retval:42
//T has-passed:no

struct S
{
    enum O
    {
        B = 21
    }
}

int main()
{
    S s;
    return s.O.B + S.O.B;
}

