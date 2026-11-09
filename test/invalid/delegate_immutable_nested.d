//T error: delegate_immutable_nested.d:9:27:
//T error: Can't cast int delegate() <{ref __ctx}> to immutable(int delegate() <{void*}>).
void f() {
	int n;
	int inc() {
		return ++n;
	}

	immutable(int delegate()) dg = inc;
}
