//T error: cast_int_to_bool_not_lvalue.d:3:2:
//T error: Expected an lvalue.

int main() {
	int i = 1;
	&cast(bool) i = true;
	return 0;
}
