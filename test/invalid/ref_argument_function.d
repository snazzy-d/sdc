//T error: ref_argument_function.d:8:3:
//T error: Can't bind a value without an address to ref void function().
void g() {}

void f(ref void function() fp);

void h() {
	f(g);
}
