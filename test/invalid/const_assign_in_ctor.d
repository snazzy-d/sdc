//T error: const_assign_in_ctor.d:5:2:
//T error: Can't modify const(int).
struct S {
	this(const(int)* p) {
		*p = 1;
	}
}
