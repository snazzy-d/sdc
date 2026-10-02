//T error: ref_bit_cast.d:10:6:
//T error: Argument isn't a lvalue.

void take(ref uint x) {
	x = 1;
}

int main() {
	int i = 0;
	take(i);
	return 0;
}
