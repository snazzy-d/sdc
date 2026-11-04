//T error: ref_argument_qualifier_const_shared_to_const.d:6:3:
//T error: Can't bind shared(const(int)) to ref const(int).
void g(ref const(int) x);

void f(ref const(shared(int)) x) {
	g(x);
}
