//T error: function_return_ref.d:6:16:
//T error: Can't cast ref int function() to int function().
ref int f();

auto g() {
	int function() fp = &f;
	return fp;
}
