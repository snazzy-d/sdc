//T error: foreach_ref_immutable_shared.d:4:10:
//T error: Can't bind element of type immutable(int) by ref to shared(const(int)).
void f(immutable(int)[] a) {
	foreach (ref const(shared(int)) e; a) {}
}
