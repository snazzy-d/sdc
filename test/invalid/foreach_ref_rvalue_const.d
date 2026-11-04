//T error: foreach_ref_rvalue_const.d:10:10:
//T error: Can't bind a value without an address to ref const(int).
int[3] make() {
	int[3] a = [1, 2, 3];
	return a;
}

int main() {
	int sum = 0;
	foreach (ref const(int) e; make()) {
		sum += e;
	}

	return sum;
}
