//T error: catch_not_a_class.d:8:10:
//T error: x is not a class.

void main() {
	int x;
	try {
		throw new Exception();
	} catch (x) {}
}
