//T error: this_not_consumed_paren.d:10:2:
//T error: nope can't be resolved in type S.

struct S {
	int x;
}

void main() {
	S s;
	(s).nope;
}
