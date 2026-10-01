//T error: array_ptr_rvalue.d:10:8:
//T error: Expected an lvalue.

int[2] pair() {
	int[2] a;
	return a;
}

int main() {
	return pair().ptr;
}
