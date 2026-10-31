//T error: ref_argument_rvalue.d:6:3:
//T error: Argument isn't a lvalue.
void f(ref int x);

void g() {
	f(1);
}
