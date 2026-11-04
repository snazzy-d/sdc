//T error: ref_argument_qualifier_const_to_immutable.d:6:3:
//T error: Can't bind const(int) to ref immutable(int).
void g(ref immutable(int) x);

void f(ref const(int) x) {
	g(x);
}
