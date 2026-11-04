//T error: pointer_qualifier_shared_to_const.d:4:1:
//T error: Can't cast shared(int)* to const(int)*.
const(int)* f(shared(int)* x) {
	return x;
}
