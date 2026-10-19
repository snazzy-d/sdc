//T error: cast_qualifier_pointer_to_const_array.d:4:1:
//T error: Can't cast const(int[2])* to int[2]*.
int[2]* f(const(int)[2]* x) {
	return x;
}
