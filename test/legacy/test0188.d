//T compiles:yes
//T retval:42
//T has-passed:yes
// Tests default value for arguments.

uint add(uint a, uint b = 7) {
	return a + b;
}

int main() {
	return add(23) + add(4, 8);
}
