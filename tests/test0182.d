//T compiles:yes
//T has-passed:no
//T retval:9
// array ~= element;

int sumArray(int[] arr) {
	int acc;
	foreach(v;arr) {
		acc += v; 
	}
	return acc;
}


int main() {
	int[] a;
	a ~= 1;
	a ~= 2;
	a ~= 3;
	return sumArray(a) + a.length;
}

