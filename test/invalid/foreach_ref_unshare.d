//T error: foreach_ref_unshare.d:4:10:
//T error: Can't bind shared(int) to ref int.
void f(shared(int)[] a) {
	foreach (ref int e; a) {}
}
