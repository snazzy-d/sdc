//T error: delegate_shared_constructor_parameter.d:7:2:
//T error: Can't cast int delegate() <{void*}> to shared(int delegate() <{void*}>).
class K {
	int delegate() dg;

	this(int delegate() d) shared {
		dg = d;
	}
}
