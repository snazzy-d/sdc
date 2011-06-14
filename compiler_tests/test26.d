//T compiles:yes
//T retval:2

int main()
{
    int i;
    void* p = &i;
    return *(cast(int*) p) + 2;
}
