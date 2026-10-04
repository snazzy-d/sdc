//T error: slice_non_sliceable.d:6:10:
//T error: Can't slice int.

int main() {
	int i = 1;
	auto s = i[0 .. 1];
	return 0;
}
