//T error: this_not_consumed_class.d:10:1:
//T error: *&c has not been consumed.

class C {
	int x;
}

void main() {
	C c = new C();
	c.nope;
}
