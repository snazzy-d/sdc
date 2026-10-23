//T error: immutable_assign.d:4:1:
//T error: Can't modify immutable(int).
void f(immutable int x) {
	x = 1;
}
