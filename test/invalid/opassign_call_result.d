//T error: opassign_call_result.d:8:1:
//T error: Expected an lvalue.
int f() {
	return 42;
}

void test() {
	f() += 1;
}
