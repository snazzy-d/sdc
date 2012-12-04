//T compiles:yes
//T has-passed:no
//T retval:23

string s1 = "some string";

int main()
{
    string s2 = "other string";
    return (s1 ~ s2).length;
}

