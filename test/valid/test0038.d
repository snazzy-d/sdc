//T compiles:yes
//T has-passed:no
//T retval:12

int main() {
	int[] l = new int[1024];
	int a = 768;
	l[512] = 10;
	l[5] = 1;
	l[a] = 3;

	return l[512] + l[a] - l[7 - 2];
}
