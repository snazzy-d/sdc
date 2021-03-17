//T compiles:yes
//T has-passed:yes
//T retval:42

int main() {
	auto a = foo!bool() + foo!byte() + foo!ushort() + foo!int() + foo!float();
	assert(a == 40);

	a += foo!char();

	auto b = foo!long() + foo!double();
	assert(b == 512);

	return a + b;
}

uint foo(T)() {
	static if (buzz(T.sizeof) > 10) {
		uint ret = buzz(T.sizeof);
		return ret;
	} else {
		uint ret = T.sizeof / 2;
		return (ret + 1) * 2;
	}
}

uint buzz(size_t sizeof) {
	uint ret = 1;
	for (uint i = 0; i < sizeof; ++i) {
		ret *= 2;
	}

	return ret;
}
