//T error: assign_address_of_final.d:6:3:
//T error: Expected an lvalue.

class C {
	int bump() {
		&this = this;
	}
}
