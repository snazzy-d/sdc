//T error: catch_type.d:8:10:
//T error: I is not a class.

void main() {
	alias I = int;
	try {
		throw new Exception();
	} catch (I) {}
}
