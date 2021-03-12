//T compiles:no
//T has-passed:yes

void foo(ref int i) {
	i = 42;
}

int main() {
	const int i = 21;
	foo(i);
	return i;
}
