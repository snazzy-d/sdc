//T error: this_not_consumed_aliasthis.d:15:1:
//T error: *&s has not been consumed.

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
