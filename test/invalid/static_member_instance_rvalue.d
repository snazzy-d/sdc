//T error: static_member_instance_rvalue.d:10:1:
//T error: Expected an lvalue.

struct S {
	static int g;
}

S bar();
void foo(S s) {
	bar().g = 1;
}
