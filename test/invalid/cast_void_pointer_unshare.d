//T error: cast_void_pointer_unshare.d:4:1:
//T error: Can't cast shared(int)* to void*.
void* f(shared(int)* p) {
	return p;
}
