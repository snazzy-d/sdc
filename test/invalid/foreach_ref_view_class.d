//T error: foreach_ref_view_class.d:7:10:
//T error: Can't bind B to ref A.
class A {}
class B : A {}

void f(B[] a) {
	foreach (ref A e; a) {}
}
