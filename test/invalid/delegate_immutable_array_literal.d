//T error: delegate_immutable_array_literal.d:4:29:
//T error: Can't cast int delegate() <{void*}> to immutable(int delegate() <{void*}>).
void f(int delegate() dg) {
	immutable(int delegate())[] a = [dg];
}
