//T error: delegate_immutable_return.d:4:1:
//T error: Can't cast int delegate() <{void*}> to immutable(int delegate() <{void*}>).
immutable(int delegate()) f(int delegate() dg) {
	return dg;
}
