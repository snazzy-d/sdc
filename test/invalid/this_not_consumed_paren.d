//T error: this_not_consumed_paren.d:10:2:
//T error: *&s has not been consumed.

struct S {
	int x;
}

void main() {
	S s;
	(s).nope;
}
