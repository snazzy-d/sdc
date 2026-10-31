//T error: function_return_unconst.d:6:17:
//T error: Can't cast const(int)* function() to int* function().
const(int)* f();

auto g() {
	int* function() fp = &f;
	return fp;
}
