//T error: static_member_instance_address.d:9:11:
//T error: Expected an lvalue.

struct S {
	static int g;
}

void foo(S s) {
	int* p = &s.g;
}
