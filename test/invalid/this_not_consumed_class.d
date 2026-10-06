//T error: this_not_consumed_class.d:10:1:
//T error: nope can't be resolved in type Object.

class C {
	int x;
}

void main() {
	C c = new C();
	c.nope;
}
