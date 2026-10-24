//T error: cast_explicit_pointer_const_to_immutable.d:4:11:
//T error: Expected an lvalue.
void f(const(int)* x) {
	auto p = &cast(immutable(int)*) x;
}
