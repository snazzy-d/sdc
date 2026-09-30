//T error: deref_non_pointer.d:6:8:
//T error: Only pointers can be dereferenced.

int main() {
	int a = 0;
	return *a;
}
