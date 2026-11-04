//T error: ref_return_view_uint.d:4:1:
//T error: Can't bind int to ref uint.
ref uint f(ref int x) {
	return x;
}
