//T error: this_not_consumed_pointer.d:10:1:
//T error: nope can't be resolved in type S*.

struct S {
	int x;
}

void main() {
	S* p;
	p.nope;
}
