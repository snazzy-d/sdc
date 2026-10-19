//T compiles:yes
//T has-passed:yes
//T retval:41

auto add(int a, int b) {
	return a + b;
}

auto f() {
	return cast(ulong) 64;
}

int main() {
	ulong l = f();
	return add(20, 21);
}
