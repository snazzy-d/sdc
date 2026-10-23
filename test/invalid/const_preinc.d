//T error: const_preinc.d:4:1:
//T error: Can't modify const(int).
void f(const(int)* p) {
	++*p;
}
