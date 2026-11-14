//T error: static_member_instance_index.d:9:1:
//T error: Expected an lvalue.

struct S {
	static int[1] a;
}

void foo(S s) {
	s.a[0] = 1;
}
