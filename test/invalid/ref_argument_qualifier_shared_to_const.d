//T error: ref_argument_qualifier_shared_to_const.d:6:3:
//T error: Can't bind shared(int) to ref const(int).
void g(ref const(int) x);

void f(ref shared(int) x) {
	g(x);
}
