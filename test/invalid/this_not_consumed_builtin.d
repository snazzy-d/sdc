//T error: this_not_consumed_builtin.d:6:1:
//T error: *&i has not been consumed.

void main() {
	int i;
	i.nope;
}
