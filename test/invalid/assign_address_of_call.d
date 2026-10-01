//T error: assign_address_of_call.d:10:2:
//T error: Expected an lvalue.

ref int slot() {
	static int x;
	return x;
}

int main() {
	&slot() = 1;
}
