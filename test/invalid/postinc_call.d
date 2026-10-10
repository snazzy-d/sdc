//T error: postinc_call.d:9:8:
//T error: Expected an lvalue.

int g() {
	return 42;
}

int f() {
	return g()++;
}
