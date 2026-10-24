//T error: cast_explicit_pointer_slice_const.d:4:11:
//T error: Expected an lvalue.
void f(int*[] x) {
	auto p = &cast(const(int)*[]) x;
}
