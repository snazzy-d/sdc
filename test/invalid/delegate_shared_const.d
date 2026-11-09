//T error: delegate_shared_const.d:4:31:
//T error: Can't cast int delegate() <{void*}> to shared(const(int delegate() <{void*}>)).
void f(int delegate() dg) {
	const(shared(int delegate())) sdg = dg;
}
