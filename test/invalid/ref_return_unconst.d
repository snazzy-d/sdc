//T error: ref_return_unconst.d:4:1:
//T error: Can't bind const(int) to ref int.
ref int f(ref const(int) x) {
	return x;
}
