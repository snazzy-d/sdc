//T error: ref_return_unshare.d:4:1:
//T error: Cannot ref return lvalues
ref int f(ref shared(int) x) {
	return x;
}
