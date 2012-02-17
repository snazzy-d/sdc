//T compiles:no
//T retval:42

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

