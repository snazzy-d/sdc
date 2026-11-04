//T error: ref_return_share.d:4:1:
//T error: Can't bind int to ref shared(int).
ref shared(int) f(ref int x) {
	return x;
}
