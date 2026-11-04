//T error: ref_return_unshare.d:4:1:
//T error: Can't bind shared(int) to ref int.
ref int f(ref shared(int) x) {
	return x;
}
