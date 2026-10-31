//T error: ref_argument_rvalue_const.d:8:3:
//T error: Argument isn't a lvalue.
void f(ref const(int) x);

int h();

void g() {
	f(h());
}
