//T error: static_member_instance_assign.d:9:1:
//T error: Expected an lvalue.

struct S {
	static int g;
}

void foo(S s) {
	s.g = 1;
}
