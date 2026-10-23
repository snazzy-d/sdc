//T error: const_assign_pointer.d:4:1:
//T error: Can't modify const(int).
void f(const(int)* p) {
	*p = 1;
}
