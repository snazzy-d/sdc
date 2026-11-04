//T error: pointer_qualifier_const_shared_to_const.d:4:1:
//T error: Can't cast shared(const(int))* to const(int)*.
const(int)* f(const(shared(int))* x) {
	return x;
}
