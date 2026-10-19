//T error: cast_qualifier_const_slice.d:4:1:
//T error: Can't cast const(int)[] to int[].
int[] f(const(int)[] x) {
	return x;
}
