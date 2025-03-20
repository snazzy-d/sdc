//T error: ifti_arity_error.d:9:1:
//T error: No match

bool foo(T)(T x) {
	return x != 0;
}

void main() {
	foo(1, 2);
}
