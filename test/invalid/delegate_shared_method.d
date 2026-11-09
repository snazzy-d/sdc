//T error: delegate_shared_method.d:12:24:
//T error: Can't cast int delegate() <{ref S}> to shared(int delegate() <{void*}>).
struct S {
	int n;

	int inc() {
		return ++n;
	}
}

void f(ref S s) {
	shared(int delegate()) dg = s.inc;
}
