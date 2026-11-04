//T error: foreach_ref_view_shared_uint.d:4:10:
//T error: Can't bind shared(int) to ref shared(uint).
void f(shared(int)[] a) {
	foreach (ref shared(uint) e; a) {}
}
