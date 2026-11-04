//T error: ref_argument_qualifier_const_to_shared.d:6:3:
//T error: Can't bind const(int) to ref shared(int).
void g(ref shared(int) x);

void f(ref const(int) x) {
	g(x);
}
