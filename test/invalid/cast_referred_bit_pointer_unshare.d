//T error: cast_referred_bit_pointer_unshare.d:4:1:
//T error: Can't cast shared(int)* to uint*.
uint* f(shared(int)* p) {
	return p;
}
