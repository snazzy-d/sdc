//T error: cast_array_element_widen.d:4:8:
//T error: Can't cast int[2] to long[2].
long[2] f(int[2] x) {
	return cast(long[2]) x;
}
