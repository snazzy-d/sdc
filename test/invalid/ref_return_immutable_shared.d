//T error: ref_return_immutable_shared.d:4:1:
//T error: Cannot ref return lvalues
ref const(shared(int)) f(ref immutable(int) x) {
	return x;
}
