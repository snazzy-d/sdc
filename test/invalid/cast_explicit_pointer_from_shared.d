//T error: cast_explicit_pointer_from_shared.d:4:11:
//T error: Expected an lvalue.
void f(shared(int)* x) {
	auto p = &cast(int*) x;
}
