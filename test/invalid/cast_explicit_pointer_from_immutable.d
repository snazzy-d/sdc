//T error: cast_explicit_pointer_from_immutable.d:4:11:
//T error: Expected an lvalue.
void f(immutable(int)* x) {
	auto p = &cast(int*) x;
}
