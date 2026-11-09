//T error: delegate_immutable_argument.d:6:3:
//T error: Can't cast int delegate() <{void*}> to immutable(int delegate() <{void*}>).
void g(immutable(int delegate()) dg);

void f(int delegate() dg) {
	g(dg);
}
