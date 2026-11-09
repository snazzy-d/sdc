//T error: delegate_immutable_method.d:12:27:
//T error: Can't cast int delegate() <{ref S}> to immutable(int delegate() <{void*}>).
struct S {
	int n;

	int inc() {
		return ++n;
	}
}

void f(ref S s) {
	immutable(int delegate()) dg = s.inc;
}
