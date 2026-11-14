//T error: static_member_instance_ref_argument.d:10:5:
//T error: Can't bind a value without an address to ref int.

struct S {
	static int g;
}

void bar(ref int i);
void foo(S s) {
	bar(s.g);
}
