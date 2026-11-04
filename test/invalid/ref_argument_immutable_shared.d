//T error: ref_argument_immutable_shared.d:6:3:
//T error: Can't pass argument (immutable(int)) by ref to ref shared(const(int)).
void g(ref const(shared(int)) x);

void f(ref immutable(int) x) {
	g(x);
}
