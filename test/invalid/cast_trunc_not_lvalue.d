//T error: cast_trunc_not_lvalue.d:7:2:
//T error: Expected an lvalue.

int main() {
	int i = 1;
	byte b;
	&cast(byte) i = b;
	return 0;
}
