//T error: this_not_consumed_typealias.d:9:11:
//T error: *&s has not been consumed.
struct S {
	struct T {}
}

void foo() {
	S s;
	alias A = s.T;
	A a;
}
