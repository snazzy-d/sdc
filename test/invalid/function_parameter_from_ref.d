//T error: function_parameter_from_ref.d:6:20:
//T error: Can't cast void function(ref int) to void function(int).
void f(ref int x);

auto g() {
	void function(int) fp = &f;
	return fp;
}
