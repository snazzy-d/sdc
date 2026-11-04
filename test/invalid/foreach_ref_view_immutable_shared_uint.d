//T error: foreach_ref_view_immutable_shared_uint.d:4:10:
//T error: Can't bind immutable(int) to ref shared(uint).
void f(immutable(int)[] a) {
	foreach (ref shared(uint) e; a) {}
}
