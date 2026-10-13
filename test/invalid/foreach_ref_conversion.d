//T error: foreach_ref_conversion.d:5:10:
//T error: Can't bind element of type int by ref to long.
int main() {
	int[] arr = [10, 20, 30];
	foreach (ref long e; arr) {
		e = 5;
	}

	return cast(int) arr[0];
}
