//T error: cast_explicit_pointer_to_shared.d:4:11:
//T error: Expected an lvalue.
void f(int* x) {
	auto p = &cast(shared(int)*) x;
}
