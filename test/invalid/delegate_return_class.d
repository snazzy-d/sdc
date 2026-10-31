//T error: delegate_return_class.d:7:1:
//T error: Can't cast A delegate() <{void*}> to B delegate() <{void*}>.
class A {}
class B : A {}

B delegate() g(A delegate() d) {
	return d;
}
