//T error: ref_argument_slice_const.d:6:3:
//T error: Can't bind int[] to ref const(int)[].
void f(ref const(int)[] x);

void g(int[] y) {
	f(y);
}
