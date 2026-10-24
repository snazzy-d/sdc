//T error: cast_explicit_unshare.d:4:11:
//T error: Expected an lvalue.
void f(shared(int) x) {
	auto p = &cast(int) x;
}
