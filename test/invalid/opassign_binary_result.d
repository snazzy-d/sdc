//T error: opassign_binary_result.d:5:2:
//T error: Expected an lvalue.
void test() {
	int a = 1, b = 2;
	(a + b) += 1;
}
