//T error: ref_argument_function_address.d:8:4:
//T error: Can't bind a value without an address to ref void function().
void g() {}

void f(ref void function() fp);

void h() {
	f(&g);
}
