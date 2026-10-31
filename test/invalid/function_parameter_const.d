//T error: function_parameter_const.d:6:28:
//T error: Can't cast void function(int*) to void function(const(int)*).
void f(int* p);

auto g() {
	void function(const(int)*) fp = &f;
	return fp;
}
