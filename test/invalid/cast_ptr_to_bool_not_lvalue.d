//T error: cast_ptr_to_bool_not_lvalue.d:4:2:
//T error: Expected an lvalue.

int main() {
	int i;
	int* p = &i;
	&cast(bool) p = true;
	return 0;
}
