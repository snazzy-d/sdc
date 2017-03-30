//T compiles:yes
//T has-passed:yes
//T retval:14
// tpl template argument specialization.

auto qux(uint N)(uint[N] a) {
	return N;
}

auto buzz(T)(T[10] a) {
	return uint(T.sizeof);
}

int main() {
	uint[10] a;
	return buzz(a) + qux(a);
}
