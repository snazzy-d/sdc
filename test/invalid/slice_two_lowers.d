//T error: slice_two_lowers.d:6:10:
//T error: Slice needs one lower and one upper bound.

int main() {
	int[4] a;
	auto s = a[0, 1 .. 2];
	return 0;
}
