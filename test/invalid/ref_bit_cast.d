//T error: ref_bit_cast.d:10:6:
//T error: Can't pass argument (int) by ref to ref uint.

void take(ref uint x) {
	x = 1;
}

int main() {
	int i = 0;
	take(i);
	return 0;
}
