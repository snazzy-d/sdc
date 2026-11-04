//T error: ref_argument_unconst.d:6:3:
//T error: Can't bind const(int) to ref int.
void f(ref int x);

void g(const(int) y) {
	f(y);
}
