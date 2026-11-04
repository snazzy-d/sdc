//T error: ref_return_qualifier.d:4:1:
//T error: Can't bind int* to ref const(int)*.
ref const(int)* f(ref int* x) {
	return x;
}
