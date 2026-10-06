//T error: this_not_consumed_array.d:6:1:
//T error: *&a has not been consumed.

void main() {
	int[3] a;
	a.nope;
}
