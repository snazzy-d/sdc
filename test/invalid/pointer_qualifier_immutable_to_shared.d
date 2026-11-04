//T error: pointer_qualifier_immutable_to_shared.d:4:1:
//T error: Can't cast immutable(int)* to shared(int)*.
shared(int)* f(immutable(int)* x) {
	return x;
}
