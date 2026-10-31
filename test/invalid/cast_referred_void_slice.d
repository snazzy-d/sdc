//T error: cast_referred_void_slice.d:4:1:
//T error: Can't cast int*[] to void*[].
void*[] f(int*[] s) {
	return s;
}
