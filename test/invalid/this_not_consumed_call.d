//T error: this_not_consumed_call.d:9:1:
//T error: nope can't be resolved in type int.

int foo() {
	return 1;
}

void main() {
	foo().nope;
}
