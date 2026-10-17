//T error: foreach_ref_shared.d:5:10:
//T error: Can't bind element of type shared(int) by ref to const(int).
int main() {
	shared(int)[] arr;
	foreach (ref const(int) e; arr) {
		return e;
	}

	return 0;
}
