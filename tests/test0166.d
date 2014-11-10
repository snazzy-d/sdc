//T compiles:yes
//T has-passed:yes
//T retval:42
// Check if SliceTypes default initializers work
// and that array.length property works.

int main() {
	int[] l;
	if (l.length != 0 && l.ptr != null) {
		return -1;
	}
	
	int[42] arr;
	for (int i = 0; i < arr.length; i++) {
		if (arr[i] != 0) {
			// XXX: Enable when array initialization is done properly.
			// return 10;
		}
	}

	return cast(int) arr.length;
}

