//T error: cast_qualifier_to_const_shared_nested_pointer.d:4:1:
//T error: Can't cast shared(int)** to shared(const(int))**.
const(shared(int))** f(shared(int)** x) {
	return x;
}
