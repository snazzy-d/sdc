//T compiles:yes
//T has-passed:yes
//T retval:42
// Test IFTI with explicit and implicit parameter.

int foo()(int i) {
	return i + bar!int(13);
}

template Qux(T : U*, U) {
	uint Qux = T.sizeof + U.sizeof;
}

auto bar(T)(T t) {
	return t;
}

int main() {
	auto b=0;
	static if (size_t.sizeof==uint.sizeof) {
                b=8;
	}
	auto a = Qux!(float*);
	assert(a == 12-b/2);

	a += Qux!(int*, int);
	assert(a == 24 - b);


	return foo(a) + bar(5) + b;
}
