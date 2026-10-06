//T error: this_not_consumed_nenum.d:12:1:
//T error: Cannot use an expression to access E.

struct S {
	enum E {
		a,
	}
}

void main() {
	S s;
	s.E;
}
