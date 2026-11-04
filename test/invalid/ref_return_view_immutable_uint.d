//T error: ref_return_view_immutable_uint.d:4:1:
//T error: Can't bind immutable(int) to ref uint.
ref uint f(ref immutable(int) x) {
	return x;
}
