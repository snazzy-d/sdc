//T compiles:yes
//T retval:42
//T known:yes

int main()
{
    int i = 0;
FOO:
    i++;
    if (i != 42) {
        if (i == 27) {
            i = 27;
        }
        goto FOO;
    }
    return i;
}

