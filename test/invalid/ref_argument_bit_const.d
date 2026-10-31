//T error: ref_argument_bit_const.d:6:3:
//T error: Can't pass argument (int) by ref to ref const(uint).
void f(ref const(uint) x);

void g(int y) {
	f(y);
}
