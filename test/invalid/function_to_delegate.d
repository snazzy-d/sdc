//T error: function_to_delegate.d:6:16:
//T error: Can't cast int function() to int delegate() <{void*}>.
int f();

auto g() {
	int delegate() fp = &f;
	return fp;
}
