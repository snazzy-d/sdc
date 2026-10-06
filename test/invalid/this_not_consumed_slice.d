//T error: this_not_consumed_slice.d:6:1:
//T error: nope can't be resolved in type int[].

void main() {
	int[] a;
	a.nope;
}
