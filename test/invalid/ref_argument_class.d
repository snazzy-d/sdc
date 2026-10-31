//T error: ref_argument_class.d:9:3:
//T error: Can't pass argument (B) by ref to ref A.
class A {}
class B : A {}

void f(ref A x);

void g(B y) {
	f(y);
}
