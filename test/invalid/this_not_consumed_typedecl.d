//T error: this_not_consumed_typedecl.d:9:1:
//T error: Cannot use an expression to access T.
struct S {
	struct T {}
}

void foo() {
	S s;
	s.T t;
}
