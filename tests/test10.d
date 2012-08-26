//T compiles:yes
//T retval:12
// Tests typeof and evaluation of expressions with no side-effects.

int main()
{
    int i = 12;
    typeof(i) j;
    typeof(i++) k;
    return i;
}
