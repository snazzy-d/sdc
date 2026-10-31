//T error: delegate_parameter_class.d:7:1:
//T error: Can't cast void delegate(B) <{void*}> to void delegate(A) <{void*}>.
class A {}
class B : A {}

void delegate(A) g(void delegate(B) d) {
	return d;
}
