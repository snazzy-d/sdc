//T error: ref_argument_function_address.d:8:4:
//T error: Argument isn't a lvalue.
void g() {}

void f(ref void function() fp);

void h() {
	f(&g);
}
