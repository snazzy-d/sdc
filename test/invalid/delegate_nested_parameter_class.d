//T error: delegate_nested_parameter_class.d:9:1:
//T error: Can't cast void delegate(B) <{ref __ctx}> to void delegate(A) <{void*}>.
class A {}
class B : A {}

void delegate(A) g() {
	void take(B b) {}

	return take;
}
