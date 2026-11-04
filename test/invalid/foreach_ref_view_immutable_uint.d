//T error: foreach_ref_view_immutable_uint.d:4:10:
//T error: Can't bind immutable(int) to ref uint.
void f(immutable(int)[] a) {
	foreach (ref uint e; a) {}
}
