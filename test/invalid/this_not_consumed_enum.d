//T error: this_not_consumed_enum.d:11:1:
//T error: nope can't be resolved in type int.

enum E {
	a,
	b,
}

void main() {
	E e = E.a;
	e.nope;
}
