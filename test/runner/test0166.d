//T compiles:yes
//T has-passed:yes
//T retval:42
// Check slice and array default initializers
// and that array.length works.

int main() {
	int[] l;
	if (l.length != 0 && l.ptr != null) {
		return -1;
	}

	int[42] arr;
	for (int i = 0; i < arr.length; i++) {
		if (arr[i] != 0) {
			return 10;
		}
	}

	return arr.length;
}
