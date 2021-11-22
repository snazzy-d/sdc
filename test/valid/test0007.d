//T compiles:yes
//T retval:1
//T has-passed:yes
// Tests increment on types smaller than int.

int main() {
	byte b;
	b++;

	return b;
}
