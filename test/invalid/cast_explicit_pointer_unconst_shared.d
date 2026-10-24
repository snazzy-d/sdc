//T error: cast_explicit_pointer_unconst_shared.d:4:11:
//T error: Expected an lvalue.
void f(const(shared(int))* x) {
	auto p = &cast(shared(int)*) x;
}
