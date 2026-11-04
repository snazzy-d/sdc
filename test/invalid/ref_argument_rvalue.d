//T error: ref_argument_rvalue.d:6:3:
//T error: Can't bind a value without an address to ref int.
void f(ref int x);

void g() {
	f(1);
}
