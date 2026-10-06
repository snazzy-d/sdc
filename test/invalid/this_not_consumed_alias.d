//T error: this_not_consumed_alias.d:10:1:
//T error: Cannot use an expression to access T.

struct S {
	alias T = int;
}

void main() {
	S s;
	s.T;
}
