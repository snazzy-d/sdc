//T error: this_not_consumed_typeenum.d:11:1:
//T error: Cannot use an expression to access E.
struct S {
	enum E {
		a,
	}
}

void foo() {
	S s;
	s.E e;
}
