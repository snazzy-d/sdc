//T error: address_of_rvalue.d:5:9:
//T error: Expected an lvalue.

int* foo() {
	return &1;
}
