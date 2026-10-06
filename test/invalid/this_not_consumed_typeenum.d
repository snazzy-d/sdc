//T error: this_not_consumed_typeenum.d:11:1:
//T error: *&s has not been consumed.
struct S {
	enum E {
		a,
	}
}

void foo() {
	S s;
	s.E e;
}
