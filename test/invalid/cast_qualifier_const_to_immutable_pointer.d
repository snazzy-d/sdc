//T error: cast_qualifier_const_to_immutable_pointer.d:4:1:
//T error: Can't cast const(int)* to immutable(int)*.
immutable(int)* f(const(int)* x) {
	return x;
}
