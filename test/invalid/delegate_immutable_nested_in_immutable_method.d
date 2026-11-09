//T error: delegate_immutable_nested_in_immutable_method.d:10:28:
//T error: Can't cast int delegate() <{ref __ctx}> to immutable(int delegate() <{void*}>).
class C {
	void m() immutable {
		int n;
		int inc() {
			return ++n;
		}

		immutable(int delegate()) dg = inc;
	}
}
