//T error: function_ref_parameter_class.d:9:22:
//T error: Can't cast void function(ref A) to void function(ref B).
class A {}
class B : A {}

void f(ref A a);

auto g() {
	void function(ref B) fp = &f;
	return fp;
}
