//T error: ref_argument_pointer_immutable.d:6:3:
//T error: Can't pass argument (immutable(int)*) by ref to ref const(int)*.
void f(ref const(int)* x);

void g(immutable(int)* y) {
	f(y);
}
