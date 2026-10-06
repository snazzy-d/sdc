//T error: this_not_consumed_typealiasmem.d:9:1:
//T error: Cannot use an expression to access A.
struct S {
	alias A = int;
}

void foo() {
	S s;
	s.A a;
}
