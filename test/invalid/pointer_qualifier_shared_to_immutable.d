//T error: pointer_qualifier_shared_to_immutable.d:4:1:
//T error: Can't cast shared(int)* to immutable(int)*.
immutable(int)* f(shared(int)* x) {
	return x;
}
