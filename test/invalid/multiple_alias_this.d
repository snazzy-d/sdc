//T error: WTF am I supposed to do here ?

struct Inner1 {
	int x;
}

struct Inner2 {
	int x;
}

struct S {
	Inner1 i1;
	Inner2 i2;
	alias i1 this;
	alias i2 this;
}

void main() {
	S s;
	s.x;
}
