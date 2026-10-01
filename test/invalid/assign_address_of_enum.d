//T error: assign_address_of_enum.d:7:2:
//T error: Expected an lvalue.

enum int answer = 42;

int main() {
	&answer = 1;
}
