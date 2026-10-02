//T error: assign_address_of_variable.d:6:2:
//T error: Expected an lvalue.

int main() {
	int a;
	&a = 1;
}
