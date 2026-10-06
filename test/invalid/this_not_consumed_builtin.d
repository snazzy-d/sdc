//T error: this_not_consumed_builtin.d:6:1:
//T error: nope can't be resolved in type int.

void main() {
	int i;
	i.nope;
}
