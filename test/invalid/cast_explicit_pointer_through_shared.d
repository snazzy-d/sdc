//T error: cast_explicit_pointer_through_shared.d:4:11:
//T error: Expected an lvalue.
void f(shared(int)* x) {
	auto p = &cast(int*) cast(shared(int*)) x;
}
