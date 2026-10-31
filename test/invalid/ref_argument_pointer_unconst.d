//T error: ref_argument_pointer_unconst.d:6:3:
//T error: Can't pass argument (const(int)*) by ref to ref int*.
void f(ref int* x);

void g(const(int)* y) {
	f(y);
}
