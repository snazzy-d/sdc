//T error: ref_argument_share.d:6:3:
//T error: Can't pass argument (int) by ref to ref shared(int).
void f(ref shared(int) x);

void g(int y) {
	f(y);
}
