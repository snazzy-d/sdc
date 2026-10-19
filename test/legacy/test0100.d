//T compiles:yes
//T has-passed:yes
//T retval:42

int main() {
	auto a = foo!bool() + foo!byte() + foo!ushort() + foo!int() + foo!float();
	assert(a == 10);

	a += foo!char();

	auto b = foo!long() + foo!double();

	assert(b == 30);

	return a + b;
}

uint foo(T)() {
	static if (buzz(T.sizeof)) {
		return 15;
	} else {
		return 2;
	}
}

bool buzz(size_t sizeof) {
	if (sizeof > 4) {
		return true;
	} else {
		return false;
	}
}
