//T error: cast_explicit_slice_to_immutable.d:4:11:
//T error: Expected an lvalue.
void f(int[] x) {
	auto p = &cast(immutable(int)[]) x;
}
