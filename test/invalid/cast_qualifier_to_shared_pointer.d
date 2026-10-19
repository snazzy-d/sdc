//T error: cast_qualifier_to_shared_pointer.d:4:1:
//T error: Can't cast int* to shared(int)*.
shared(int)* f(int* x) {
	return x;
}
