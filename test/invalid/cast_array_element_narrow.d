//T error: cast_array_element_narrow.d:4:8:
//T error: Can't cast long[2] to int[2].
int[2] f(long[2] x) {
	return cast(int[2]) x;
}
