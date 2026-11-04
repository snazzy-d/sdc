//T error: pointer_qualifier_mutable_to_const_shared.d:4:1:
//T error: Can't cast int* to shared(const(int))*.
const(shared(int))* f(int* x) {
	return x;
}
