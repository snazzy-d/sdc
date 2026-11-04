//T error: pointer_qualifier_const_shared_to_mutable.d:4:1:
//T error: Can't cast shared(const(int))* to int*.
int* f(const(shared(int))* x) {
	return x;
}
