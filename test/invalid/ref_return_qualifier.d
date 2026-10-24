//T error: ref_return_qualifier.d:4:1:
//T error: Cannot ref return lvalues
ref const(int)* f(ref int* x) {
	return x;
}
