//T error: ref_argument_rvalue_const.d:8:3:
//T error: Can't bind a value without an address to ref const(int).
void f(ref const(int) x);

int h();

void g() {
	f(h());
}
