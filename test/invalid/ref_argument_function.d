//T error: ref_argument_function.d:8:3:
//T error: Argument isn't a lvalue.
void g() {}

void f(ref void function() fp);

void h() {
	f(g);
}
