//T error: function_to_pointer.d:6:6:
//T error: Can't cast void function() to int*.
void f();

auto g() {
	int* fp = &f;
	return fp;
}
