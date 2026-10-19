//T error: cast_qualifier_immutable_nested_pointer.d:4:1:
//T error: Can't cast immutable(int)** to const(int)**.
const(int)** f(immutable(int)** x) {
	return x;
}
