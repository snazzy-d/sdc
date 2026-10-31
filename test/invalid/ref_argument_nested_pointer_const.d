//T error: ref_argument_nested_pointer_const.d:6:3:
//T error: Can't pass argument (int**) by ref to ref const(int)**.
void f(ref const(int)** x);

void g(int** y) {
	f(y);
}
