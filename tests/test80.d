//T compiles:yes
//T retval:8

alias int bar;

int main()
{
    return cast(int) ((int).sizeof + (bar).sizeof);
}

