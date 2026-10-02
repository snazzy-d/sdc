//T error: cast_spad_not_lvalue.d:7:2:
//T error: Expected an lvalue.

int main() {
	byte b = 1;
	int i;
	&cast(int) b = i;
	return 0;
}
