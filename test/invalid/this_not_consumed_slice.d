//T error: this_not_consumed_slice.d:6:1:
//T error: *&a has not been consumed.

void main() {
	int[] a;
	a.nope;
}
