//T error: cast_address_immutable_shared.d:4:11:
//T error: Expected an lvalue.
void f(ref immutable(int) x) {
	auto p = &cast(const(shared(int))) x;
}
