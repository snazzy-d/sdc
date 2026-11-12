//T error: pointer_declaration_cast.d:6:1:
//T error: Can't cast int to S*.
struct S {}

void f() {
	S* p = 3;
}
