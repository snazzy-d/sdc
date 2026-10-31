//T error: function_ref_parameter_bit.d:6:24:
//T error: Can't cast void function(ref uint) to void function(ref int).
void f(ref uint a);

auto g() {
	void function(ref int) fp = &f;
	return fp;
}
