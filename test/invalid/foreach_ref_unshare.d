//T error: foreach_ref_unshare.d:4:10:
//T error: Can't bind element of type shared(int) by ref to int.
void f(shared(int)[] a) {
	foreach (ref int e; a) {}
}
