//T error: cast_int_to_ptr_not_lvalue.d:6:2:
//T error: Expected an lvalue.

int main() {
	int i = 1;
	&cast(void*) i = null;
	return 0;
}
