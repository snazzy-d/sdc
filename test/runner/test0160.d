//T compiles:yes
//T retval:53
//T has-passed:yes
// cent and ucent.

int main() {
	cent c = 7;
	c++;

	ucent uc = c + 5;

	return cast(int) (c + uc + cent.sizeof + ucent.sizeof);
}
