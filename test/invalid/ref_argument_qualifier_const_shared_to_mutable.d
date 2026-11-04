//T error: ref_argument_qualifier_const_shared_to_mutable.d:6:3:
//T error: Can't bind shared(const(int)) to ref int.
void g(ref int x);

void f(ref const(shared(int)) x) {
	g(x);
}
