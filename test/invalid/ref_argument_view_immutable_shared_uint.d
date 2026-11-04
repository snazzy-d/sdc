//T error: ref_argument_view_immutable_shared_uint.d:6:3:
//T error: Can't bind immutable(int) to ref shared(uint).
void g(ref shared(uint) x);

void f(ref immutable(int) x) {
	g(x);
}
