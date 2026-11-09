//T error: delegate_immutable_from_shared.d:4:27:
//T error: Can't cast shared(int delegate() <{void*}>) to immutable(int delegate() <{void*}>).
void f(shared(int delegate()) dg) {
	immutable(int delegate()) idg = dg;
}
