//T error: assign_cast_unshare.d:4:1:
//T error: Expected an lvalue.
void f(ref shared(int) x) {
	cast(int) x = 1;
}
