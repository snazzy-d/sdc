//T error: delegate_shared_nested.d:9:24:
//T error: Can't cast int delegate() <{ref __ctx}> to shared(int delegate() <{void*}>).
void f() {
	int n;
	int inc() {
		return ++n;
	}

	shared(int delegate()) dg = inc;
}
