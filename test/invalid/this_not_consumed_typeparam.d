//T error: this_not_consumed_typeparam.d:9:10:
//T error: Cannot use an expression to access T.
struct S {
	struct T {}
}

void foo() {
	S s;
	void bar(s.T x) {}
}
