//T error: const_assign_field_pointee.d:7:2:
//T error: Can't modify const(int).
struct S {
	const(int)* p;

	this(int x) {
		*this.p = x;
	}
}
