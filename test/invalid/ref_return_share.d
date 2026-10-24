//T error: ref_return_share.d:4:1:
//T error: Cannot ref return lvalues
ref shared(int) f(ref int x) {
	return x;
}
