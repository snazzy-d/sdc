//T error: ref_argument_overload_set.d:9:4:
//T error: Argument isn't a lvalue.
void g() {}
void g(int) {}

void f(ref void function() fp);

void h() {
	f(&g);
}
