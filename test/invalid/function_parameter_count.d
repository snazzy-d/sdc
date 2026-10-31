//T error: function_parameter_count.d:6:17:
//T error: Can't cast void function(int) to void function().
void f(int x);

auto g() {
	void function() fp = &f;
	return fp;
}
