//T error: static_member_instance_immutable.d:9:1:
//T error: Can't modify immutable(int).

struct S {
	static immutable int g;
}

void foo(S s) {
	s.g = 1;
}
