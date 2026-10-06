//T error: this_not_consumed_callmem.d:10:1:
//T error: *&s has not been consumed.

struct S {
	int x;
}

void main() {
	S s;
	s.nope();
}
