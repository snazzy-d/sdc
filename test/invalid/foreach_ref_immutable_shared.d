//T error: foreach_ref_immutable_shared.d:4:10:
//T error: Can't bind immutable(int) to ref shared(int).
void f(immutable(int)[] a) {
	foreach (ref shared(int) e; a) {}
}
