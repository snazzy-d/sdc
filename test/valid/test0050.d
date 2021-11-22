//T compiles:yes
//T has-passed:yes
//T retval:42

int add(int a, int b) {
	return a + b;
}

int add(int a, int b, int c) {
	return a + b + c;
}

int main() {
	int function(int, int) a = &add;
	return a(21, 21);
}
