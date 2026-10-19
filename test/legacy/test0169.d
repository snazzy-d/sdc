//T compiles:yes
//T has-passed:yes
//T retval:23
// UFCS and getter @property + UFCS overload

@property
int ufcs(int a) {
	return a;
}

int ufcs(int* p) @property {
	return *p + 1;
}

int main() {
	int a = 11;
	return a.ufcs + (&a).ufcs;
}
