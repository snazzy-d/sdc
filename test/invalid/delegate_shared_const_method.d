//T error: delegate_shared_const_method.d:12:24:
//T error: Can't cast int delegate() <{ref const(S)}> to shared(int delegate() <{void*}>).
struct S {
	int n;

	int get() const {
		return n;
	}
}

void f(ref S s) {
	shared(int delegate()) dg = s.get;
}
