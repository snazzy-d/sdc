//T error: delegate_shared_return.d:4:1:
//T error: Can't cast int delegate() <{void*}> to shared(int delegate() <{void*}>).
shared(int delegate()) f(int delegate() dg) {
	return dg;
}
