//T error: function_parameter_widen.d:6:20:
//T error: Can't cast void function(long) to void function(int).
void f(long x);

auto g() {
	void function(int) fp = &f;
	return fp;
}
