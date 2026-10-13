//T error: ternary_non_lvalue.d:5:2:
//T error: Expected an lvalue.
void test() {
	int a = 1;
	(true ? a : 5) = 1;
}
