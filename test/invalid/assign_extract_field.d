//T error: assign_extract_field.d:15:1:
//T error: Expected an lvalue.

struct S {
	int x;
	int y;
}

S pair() {
	S s;
	return s;
}

int main() {
	pair().x = 1;
}
