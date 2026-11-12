//T error: delegate_shared_field.d:8:1:
//T error: Can't cast int delegate() <{void*}> to shared(int delegate() <{void*}>).
class K {
	int delegate() dg;
}

void f(shared(K) k, int delegate() dg) {
	k.dg = dg;
}
