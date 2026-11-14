//T error: static_member_instance_ref_return.d:9:1:
//T error: Can't bind a value without an address to ref int.

struct S {
	static int g;
}

ref int foo(S s) {
	return s.g;
}
