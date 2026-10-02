//T error: cast_bit_not_lvalue.d:4:2:
//T error: Expected an lvalue.

int main() {
	int i = 1;
	uint u;
	&cast(uint) i = u;
	return 0;
}
