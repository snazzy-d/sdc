//T error: cast_explicit_pointer_unconst.d:4:11:
//T error: Expected an lvalue.
void f(const(int)* x) {
	auto p = &cast(int*) x;
}
