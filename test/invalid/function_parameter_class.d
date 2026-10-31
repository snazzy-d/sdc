//T error: function_parameter_class.d:9:18:
//T error: Can't cast void function(B) to void function(A).
class A {}
class B : A {}

void f(B b);

auto g() {
	void function(A) fp = &f;
	return fp;
}
