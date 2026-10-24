//T error: cast_explicit_nested_pointer_from_immutable.d:4:11:
//T error: Expected an lvalue.
void f(immutable(int)** x) {
	auto p = &cast(const(int)**) x;
}
