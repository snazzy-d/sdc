//T error: cast_qualifier_pointer_slice.d:4:1:
//T error: Can't cast int*[] to const(int)*[].
const(int)*[] f(int*[] x) {
	return x;
}
