//T error: assign_extract_index.d:10:1:
//T error: Expected an lvalue.

int[2] pair() {
	int[2] a;
	return a;
}

int main() {
	pair()[0] = 1;
}
