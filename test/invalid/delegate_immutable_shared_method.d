//T error: delegate_immutable_shared_method.d:12:27:
//T error: Can't cast int delegate() <{ref shared(S)}> to immutable(int delegate() <{void*}>).
struct S {
	int n;

	int get() shared {
		return 0;
	}
}

void f(ref shared(S) s) {
	immutable(int delegate()) dg = s.get;
}
