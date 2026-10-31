//T error: cast_void_pointer_unconst.d:4:1:
//T error: Can't cast const(int)* to void*.
void* f(const(int)* p) {
	return p;
}
