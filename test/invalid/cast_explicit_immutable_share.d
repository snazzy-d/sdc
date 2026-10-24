//T error: cast_explicit_immutable_share.d:4:11:
//T error: Expected an lvalue.
void f(immutable(int) x) {
	auto p = &cast(shared(int)) x;
}
