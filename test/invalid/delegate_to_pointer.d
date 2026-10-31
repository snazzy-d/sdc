//T error: delegate_to_pointer.d:13:1:
//T error: Can't cast int delegate() <{ref S}> to void*.
class A {}
class B : A {}

struct S {
	int get() {
		return 0;
	}
}

void* g(ref S s) {
	return s.get;
}
