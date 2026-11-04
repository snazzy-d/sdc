//T error: foreach_ref_view_uint.d:4:10:
//T error: Can't bind int to ref uint.
void f(int[] a) {
	foreach (ref uint e; a) {}
}
