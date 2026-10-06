//T error: this_not_consumed_nested.d:12:1:
//T error: *&s has not been consumed.

struct S {
	struct Nested {
		int x;
	}
}

void main() {
	S s;
	s.Nested;
}
