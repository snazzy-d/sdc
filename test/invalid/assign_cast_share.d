//T error: assign_cast_share.d:4:1:
//T error: Expected an lvalue.
void f(ref int x) {
	cast(shared(int)) x = 1;
}
