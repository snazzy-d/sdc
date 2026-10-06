//T error: this_not_consumed_typealiasmem.d:9:1:
//T error: *&s has not been consumed.
struct S {
	alias A = int;
}

void foo() {
	S s;
	s.A a;
}
