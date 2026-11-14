//T error: static_member_instance_foreach_ref.d:9:10:
//T error: Can't bind a value without an address to ref int.

struct S {
	static int[1] a;
}

void foo(S s) {
	foreach (ref i; s.a) {}
}
