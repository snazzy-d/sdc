//T error: cast_explicit_share.d:4:11:
//T error: Expected an lvalue.
void f(int x) {
	auto p = &cast(shared(int)) x;
}
