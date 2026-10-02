//T error: cast_ptr_to_int_not_lvalue.d:4:2:
//T error: Expected an lvalue.

int main() {
	int i;
	int* p = &i;
	&cast(ulong) p = 0;
	return 0;
}
