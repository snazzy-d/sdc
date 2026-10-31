//T error: function_ref_parameter_qualifier.d:6:25:
//T error: Can't cast void function(ref const(int)*) to void function(ref int*).
void f(ref const(int)* p);

auto g() {
	void function(ref int*) fp = &f;
	return fp;
}
