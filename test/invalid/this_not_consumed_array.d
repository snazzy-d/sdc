//T error: this_not_consumed_array.d:6:1:
//T error: nope can't be resolved in type int[3].

void main() {
	int[3] a;
	a.nope;
}
