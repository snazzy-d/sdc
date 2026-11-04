//T error: ref_return_view_shared_uint.d:4:1:
//T error: Can't bind shared(int) to ref shared(uint).
ref shared(uint) f(ref shared(int) x) {
	return x;
}
