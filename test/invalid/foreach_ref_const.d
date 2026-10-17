//T error: foreach_ref_const.d:5:10:
//T error: Can't bind element of type const(int) by ref to int.
int main() {
	const(int)[] arr = [1, 2, 3];
	foreach (ref int e; arr) {
		e = 5;
	}

	return 0;
}
