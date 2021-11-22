//T compiles:yes
//T has-passed:yes
//T retval:42

int main() {
	auto a = Foo!bool + Foo!byte + Foo!ushort + Foo!int + Foo!float;
	assert(a == 10);

	a += Foo!char;

	auto b = Foo!long + Foo!double;

	assert(b == 30);

	return a + b;
}

template Foo(T) {
	static if (buzz(T.sizeof)) {
		enum Foo = 15;
	} else {
		enum Foo = 2;
	}
}

bool buzz(size_t sizeof) {
	if (sizeof > 4) {
		return true;
	} else {
		return false;
	}
}
