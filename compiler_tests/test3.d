//T compiles:yes
//T retval:42
// Tests casting.

int main()
{
    long a = 21; // int -> long, implicit
    int c = 21;
    return cast(int) a + c;
}
