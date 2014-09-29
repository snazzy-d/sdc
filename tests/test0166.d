//T compiles:yes
//T has-passed:no
//T retval:42
//? Check if SliceTypes default initializers work. And also, that static array .length property works.

int main() {
	int[] l;
	if (l.length != 0 && l.ptr != null) {
		return -1;
	}
	int[42] arr;
	return arr.length;
}
