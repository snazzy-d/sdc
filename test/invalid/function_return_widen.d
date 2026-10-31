//T error: function_return_widen.d:6:17:
//T error: Can't cast int function() to long function().
int f();

auto g() {
	long function() fp = &f;
	return fp;
}
