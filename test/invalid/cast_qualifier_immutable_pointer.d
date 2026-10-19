//T error: cast_qualifier_immutable_pointer.d:4:1:
//T error: Can't cast immutable(int)* to int*.
int* f(immutable(int)* x) {
	return x;
}
