//T error: this_not_consumed_enum.d:11:1:
//T error: *&e has not been consumed.

enum E {
	a,
	b,
}

void main() {
	E e = E.a;
	e.nope;
}
