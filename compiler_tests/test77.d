//T compiles:yes
//T retval:0
//T has-passed:no

void main()
{
	string str = "foobar";

    // This is narrowing, but valid.
	foreach(int i, c; str) {}
}
