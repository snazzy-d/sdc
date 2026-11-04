//T error: ref_argument_qualifier_shared_to_immutable.d:6:3:
//T error: Can't bind shared(int) to ref immutable(int).
void g(ref immutable(int) x);

void f(ref shared(int) x) {
	g(x);
}
