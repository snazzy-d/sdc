//T error: delegate_immutable_copy.d:4:27:
//T error: Can't cast int delegate() <{void*}> to immutable(int delegate() <{void*}>).
void f(int delegate() dg) {
	immutable(int delegate()) idg = dg;
}
