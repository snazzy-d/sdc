//T error: assign_call.d:9:1:
//T error: Expected an lvalue.

int foo() {
	return 0;
}

int main() {
	foo() = 1;
}
