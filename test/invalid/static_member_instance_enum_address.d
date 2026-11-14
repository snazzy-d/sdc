//T error: static_member_instance_enum_address.d:9:11:
//T error: Expected an lvalue.

struct S {
	enum e = 1;
}

void foo(S s) {
	auto p = &s.e;
}
