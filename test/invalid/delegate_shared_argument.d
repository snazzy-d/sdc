//T error: delegate_shared_argument.d:6:3:
//T error: Can't cast int delegate() <{void*}> to shared(int delegate() <{void*}>).
void g(shared(int delegate()) dg);

void f(int delegate() dg) {
	g(dg);
}
