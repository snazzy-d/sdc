//T error: static_member_instance_ptr.d:9:10:
//T error: Expected an lvalue.

struct S {
	static int[1] a;
}

void foo(S s) {
	int* p = s.a.ptr;
}
