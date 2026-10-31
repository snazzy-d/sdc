//T error: function_parameter_to_ref.d:6:24:
//T error: Can't cast void function(int) to void function(ref int).
void f(int x);

auto g() {
	void function(ref int) fp = &f;
	return fp;
}
