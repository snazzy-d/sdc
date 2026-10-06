//T error: this_not_consumed_typeparam.d:9:10:
//T error: *&s has not been consumed.
struct S {
	struct T {}
}

void foo() {
	S s;
	void bar(s.T x) {}
}
