//T error: this_not_consumed_nenum.d:12:1:
//T error: *&s has not been consumed.

struct S {
	enum E {
		a,
	}
}

void main() {
	S s;
	s.E;
}
