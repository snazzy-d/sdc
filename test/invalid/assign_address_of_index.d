//T error: assign_address_of_index.d:6:2:
//T error: Expected an lvalue.

int main() {
	int[1] a;
	&a[0] = 1;
}
