//T error: delegate_immutable_hidden.d:13:27:
//T error: Can't cast int delegate() <{void*}> to immutable(int delegate() <{void*}>).
struct S {
	int n;

	int get() immutable {
		return n;
	}
}

void f(ref immutable(S) s) {
	int delegate() dg = s.get;
	immutable(int delegate()) idg = dg;
}
