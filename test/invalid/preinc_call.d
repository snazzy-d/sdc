//T error: preinc_call.d:9:10:
//T error: Expected an lvalue.

int g() {
	return 42;
}

int f() {
	return ++g();
}
