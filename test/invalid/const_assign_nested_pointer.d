//T error: const_assign_nested_pointer.d:4:1:
//T error: Can't modify const(int*).
void f(const(int*)* p, int* q) {
	*p = q;
}
