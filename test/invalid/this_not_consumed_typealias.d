//T error: this_not_consumed_typealias.d:9:11:
//T error: Cannot use an expression to access T.
struct S {
	struct T {}
}

void foo() {
	S s;
	alias A = s.T;
	A a;
}
