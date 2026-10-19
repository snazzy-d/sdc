//T error: cast_qualifier_to_immutable_pointer.d:4:1:
//T error: Can't cast int* to immutable(int)*.
immutable(int)* f(int* x) {
	return x;
}
