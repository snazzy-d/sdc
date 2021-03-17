//T compiles:yes
//T has-passed:yes
//T retval:42

struct S {
	int c, d;
}

int main() {
	S s;
	s.c = s.d = 1;

	int c = 40;

	return c + s.c + s.d;
}
