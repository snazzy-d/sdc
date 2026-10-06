//T error: this_not_consumed_field.d:10:1:
//T error: *&&s.x has not been consumed.

struct S {
	int x;
}

void main() {
	S s;
	s.x.nope;
}
