//T compiles:yes

int main()
{
    ubyte* p;
    *p++ = cast(ubyte) 'A';
    return 0;
}

