//T error: assign_address_of_global.d:7:2:
//T error: Expected an lvalue.

int g;

int main() {
	&g = 1;
}
