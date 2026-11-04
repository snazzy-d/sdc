//T error: ref_argument_qualifier_immutable_to_shared.d:6:3:
//T error: Can't bind immutable(int) to ref shared(int).
void g(ref shared(int) x);

void f(ref immutable(int) x) {
	g(x);
}
