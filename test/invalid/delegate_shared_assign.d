//T error: delegate_shared_assign.d:6:1:
//T error: Can't cast int delegate() <{void*}> to shared(int delegate() <{void*}>).
shared(int delegate()) g;

void f(int delegate() dg) {
	g = dg;
}
