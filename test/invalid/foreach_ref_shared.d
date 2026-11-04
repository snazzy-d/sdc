//T error: foreach_ref_shared.d:5:10:
//T error: Can't bind shared(int) to ref const(int).
int main() {
	shared(int)[] arr;
	foreach (ref const(int) e; arr) {
		return e;
	}

	return 0;
}
