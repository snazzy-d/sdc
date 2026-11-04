//T error: ref_argument_qualifier_immutable_to_mutable.d:6:3:
//T error: Can't bind immutable(int) to ref int.
void g(ref int x);

void f(ref immutable(int) x) {
	g(x);
}
