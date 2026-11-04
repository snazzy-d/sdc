//T error: ref_argument_qualifier_const_to_const_shared.d:6:3:
//T error: Can't bind const(int) to ref shared(const(int)).
void g(ref const(shared(int)) x);

void f(ref const(int) x) {
	g(x);
}
