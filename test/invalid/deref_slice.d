//T error: deref_slice.d:6:8:
//T error: Only pointers can be dereferenced.

int main() {
	int[] a;
	return *a;
}
