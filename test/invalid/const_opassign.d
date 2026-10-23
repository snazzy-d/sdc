//T error: const_opassign.d:4:1:
//T error: Can't modify const(int).
void f(const int x) {
	x += 1;
}
