//T error: this_not_consumed_nested.d:12:1:
//T error: Cannot use an expression to access Nested.

struct S {
	struct Nested {
		int x;
	}
}

void main() {
	S s;
	s.Nested;
}
