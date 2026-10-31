//T error: function_return_void.d:6:17:
//T error: Can't cast int function() to void function().
int f();

auto g() {
	void function() fp = &f;
	return fp;
}
