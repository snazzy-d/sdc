//T compiles:yes
//T has-passed:yes
//T retval:42

enum {
	A = 42,
	B = A,
}

int main() {
	return B;
}
