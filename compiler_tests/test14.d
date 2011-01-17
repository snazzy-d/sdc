//T compiles:yes
//T retval:58

int main()
{
    int retval = 56;
    if (retval == 56 || retval++) {
        retval++;
    }
    if (retval != 57 && retval--) {
        retval = 32;
    }
    if (retval == 57 && retval++) {
    }
    return retval;
}
