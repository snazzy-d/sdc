//T error: ref_return_unconst.d:4:1:
//T error: Cannot ref return lvalues
ref int f(ref const(int) x) {
	return x;
}
