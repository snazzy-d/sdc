//T error: cast_explicit_array_const_pointer.d:4:11:
//T error: Expected an lvalue.
void f(const(int*)[2] x) {
	auto p = &cast(int*[2]) x;
}
