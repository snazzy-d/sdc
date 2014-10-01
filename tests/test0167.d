//T compiles:yes
//T has-passed:yes
//T retval:42
//? .length property of static arrays.
int main() {
	int[42] arr;
	return arr.length;
}
