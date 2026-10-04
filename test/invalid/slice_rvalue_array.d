//T error: slice_rvalue_array.d:12:10:
//T error: Expected an lvalue.

int[2] pair() {
	int[2] a;
	a[0] = 5;
	a[1] = 6;
	return a;
}

int main() {
	auto s = pair()[0 .. 2];
	return s.length;
}
