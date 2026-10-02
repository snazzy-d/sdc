//T error: cast_down_not_lvalue.d:11:2:
//T error: Expected an lvalue.

class A {}

class B : A {}

int main() {
	A a = new A();
	B b;
	&cast(B) a = b;
	return 0;
}
