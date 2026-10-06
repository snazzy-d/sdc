//T error: this_not_consumed_field.d:10:1:
//T error: nope can't be resolved in type int.

struct S {
	int x;
}

void main() {
	S s;
	s.x.nope;
}
