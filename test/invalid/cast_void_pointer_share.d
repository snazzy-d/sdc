//T error: cast_void_pointer_share.d:4:1:
//T error: Can't cast int* to shared(void)*.
shared(void)* f(int* p) {
	return p;
}
