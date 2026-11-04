//T error: pointer_qualifier_const_to_const_shared.d:4:1:
//T error: Can't cast const(int)* to shared(const(int))*.
const(shared(int))* f(const(int)* x) {
	return x;
}
