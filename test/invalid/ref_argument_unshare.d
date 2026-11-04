//T error: ref_argument_unshare.d:6:3:
//T error: Can't bind shared(int) to ref int.
void f(ref int x);

void g(shared(int) y) {
	f(y);
}
