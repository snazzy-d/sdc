//T compiles:yes
//T has-passed:yes
//T retval:43

struct S {
	int i;
	Sub s;

	int f() {
		return i + this.j /+ + j +/;
	}

	alias i this;
	alias s this;
	alias f this;
}

struct Sub {
	int j;
}

int foo(int i) {
	return i;
}

int main() {
	S s;
	s.i = 13;
	s.j = 17;

	return foo(s) + s();
}
