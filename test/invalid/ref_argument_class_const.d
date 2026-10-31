//T error: ref_argument_class_const.d:9:3:
//T error: Can't pass argument (B) by ref to ref const(A).
class A {}
class B : A {}

void f(ref const(A) x);

void g(B y) {
	f(y);
}
