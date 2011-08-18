//T compiles:yes
//T retval:7

int main()
{
    int i;
    i = 7;
    goto _out;
    i++;
    _out:
    return i;
}

