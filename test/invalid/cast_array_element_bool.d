//T error: cast_array_element_bool.d:4:8:
//T error: Can't cast bool[2] to int[2].
int[2] f(bool[2] x) {
	return cast(int[2]) x;
}
