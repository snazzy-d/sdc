//T error: ref_argument_overload_set.d:9:4:
//T error: Can't bind a value without an address to ref void function().
void g() {}
void g(int) {}

void f(ref void function() fp);

void h() {
	f(&g);
}
