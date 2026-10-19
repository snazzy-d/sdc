//T error: cast_qualifier_shared_pointer.d:4:1:
//T error: Can't cast shared(int)* to int*.
int* f(shared(int)* x) {
	return x;
}
