//T error: delegate_immutable_const_method.d:12:27:
//T error: Can't cast int delegate() <{ref const(S)}> to immutable(int delegate() <{void*}>).
struct S {
	int n;

	int get() const {
		return n;
	}
}

void f(ref S s) {
	immutable(int delegate()) dg = s.get;
}
