//T error: cast_qualifier_const_shared_pointer.d:4:1:
//T error: Can't cast shared(const(int))* to shared(int)*.
shared(int)* f(const(shared(int))* x) {
	return x;
}
