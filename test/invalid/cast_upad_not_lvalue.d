//T error: cast_upad_not_lvalue.d:7:2:
//T error: Expected an lvalue.

int main() {
	ubyte ub = 1;
	int i;
	&cast(int) ub = i;
	return 0;
}
