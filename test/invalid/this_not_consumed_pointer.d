//T error: this_not_consumed_pointer.d:10:1:
//T error: *&p has not been consumed.

struct S {
	int x;
}

void main() {
	S* p;
	p.nope;
}
