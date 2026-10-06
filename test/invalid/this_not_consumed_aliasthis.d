//T error: this_not_consumed_aliasthis.d:15:1:
//T error: nope can't be resolved in type S.

struct Inner {
	int x;
}

struct S {
	Inner inner;
	alias inner this;
}

void main() {
	S s;
	s.nope;
}
