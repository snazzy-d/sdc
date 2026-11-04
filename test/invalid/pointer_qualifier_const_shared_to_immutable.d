//T error: pointer_qualifier_const_shared_to_immutable.d:4:1:
//T error: Can't cast shared(const(int))* to immutable(int)*.
immutable(int)* f(const(shared(int))* x) {
	return x;
}
