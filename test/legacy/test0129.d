//T compiles:yes
//T has-passed:yes
//T retval:42
// Test IFTI with explicit and implicit parameter.

int foo()(int i) {
	return i + bar!int(9);
}

template Qux(T : U*, U) {
	uint Qux = T.sizeof + U.sizeof;
}

auto bar(T)(T t) {
	return t;
}

int main() {
	auto a = Qux!(float*);
	assert(a == 12);

	a += Qux!(int*, int);
	assert(a == 24);

	return foo(a) + bar(4) + buzz(5);
}

alias buzz = bar!uint;
