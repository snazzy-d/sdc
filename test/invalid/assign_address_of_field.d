//T error: assign_address_of_field.d:10:2:
//T error: Expected an lvalue.

struct S {
	int x;
}

int main() {
	S s;
	&s.x = 1;
}
