//T error: this_not_consumed_typedecl.d:9:1:
//T error: *&s has not been consumed.
struct S {
	struct T {}
}

void foo() {
	S s;
	s.T t;
}
