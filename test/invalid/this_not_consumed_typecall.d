//T error: this_not_consumed_typecall.d:13:1:
//T error: make() has not been consumed.
struct S {
	struct T {}
}

S make() {
	S s;
	return s;
}

void foo() {
	make().T t;
}
