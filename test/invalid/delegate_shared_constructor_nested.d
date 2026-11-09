//T error: delegate_shared_constructor_nested.d:12:7:
//T error: Can't cast int delegate() <{ref __ctx}> to shared(int delegate() <{void*}>).
class K {
	int delegate() dg;

	this() shared {
		int n;
		int inc() {
			return ++n;
		}

		dg = inc;
	}
}
