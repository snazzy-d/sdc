//T error: ref_argument_view_shared_uint.d:6:3:
//T error: Can't bind shared(int) to ref shared(uint).
void g(ref shared(uint) x);

void f(ref shared(int) x) {
	g(x);
}
