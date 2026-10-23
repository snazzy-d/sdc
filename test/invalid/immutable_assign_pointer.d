//T error: immutable_assign_pointer.d:4:1:
//T error: Can't modify immutable(int).
void f(immutable(int)* p) {
	*p = 1;
}
