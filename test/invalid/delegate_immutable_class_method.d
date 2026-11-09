//T error: delegate_immutable_class_method.d:12:27:
//T error: Can't cast int delegate() <{final C}> to immutable(int delegate() <{void*}>).
class C {
	int n;

	int inc() {
		return ++n;
	}
}

void f(C c) {
	immutable(int delegate()) dg = c.inc;
}
