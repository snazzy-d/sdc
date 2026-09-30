//T error: deref_array.d:6:8:
//T error: Only pointers can be dereferenced.

int main() {
	int[2] a;
	return *a;
}
