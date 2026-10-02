//T error: cast_uint_to_ptr_not_lvalue.d:6:2:
//T error: Expected an lvalue.

int main() {
	uint u = 1;
	&cast(void*) u = null;
	return 0;
}
