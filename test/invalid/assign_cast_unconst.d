//T error: assign_cast_unconst.d:4:1:
//T error: Expected an lvalue.
void f(ref const(int) x) {
	cast(int) x = 1;
}
