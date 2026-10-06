//T error: this_not_consumed_alias.d:10:1:
//T error: *&s has not been consumed.

struct S {
	alias T = int;
}

void main() {
	S s;
	s.T;
}
