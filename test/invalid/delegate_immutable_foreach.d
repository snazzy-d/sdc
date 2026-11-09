//T error: delegate_immutable_foreach.d:4:10:
//T error: Can't cast int delegate() <{void*}> to immutable(int delegate() <{void*}>).
void f(int delegate()[] a) {
	foreach (immutable(int delegate()) dg; a) {}
}
