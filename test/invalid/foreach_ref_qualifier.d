//T error: foreach_ref_qualifier.d:4:10:
//T error: Can't bind int* to ref const(int)*.
void f(int*[] a) {
	foreach (ref const(int)* p; a) {}
}
