//T error: static_member_instance_enum_assign.d:9:1:
//T error: Expected an lvalue.

struct S {
	enum e = 1;
}

void foo(S s) {
	s.e = 1;
}
