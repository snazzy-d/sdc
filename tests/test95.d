//T compiles:yes
//T retval:12

template Foo(T)
{
    T bar;
}

int main()
{
    Foo!int.bar = 4;
    Foo!long.bar = 2 * Foo!int.bar;
    
    Foo!int.bar = 4 + cast(typeof(Foo!int.bar)) (Foo!long.bar + Foo!ulong.bar);
    
    return Foo!int.bar;
}

