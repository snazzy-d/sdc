//T error: ref_argument_to_immutable.d:6:3:
//T error: Can't pass argument (int) by ref to ref immutable(int).
void f(ref immutable(int) x);

void g(int y) {
	f(y);
}
