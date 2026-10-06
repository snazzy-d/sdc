//T error: this_not_consumed_call.d:9:1:
//T error: foo() has not been consumed.

int foo() {
	return 1;
}

void main() {
	foo().nope;
}
