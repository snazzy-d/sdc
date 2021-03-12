//T compiles:yes
//T retval:42
//T has-passed:yes
// Tests struct member functions, implicit and explicit this.

struct S {
	int c, d;

	int add(int a, int b) {
		return a + b + c + this.d;
	}
}

int main() {
	S s;
	s.c = s.d = 1;
	return s.add(38, 2);
}
