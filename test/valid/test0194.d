//T compiles:yes
//T has-passed:yes
//T retval:53
// tpl template argument specialization.

struct S(T) {
	T t;

	this(T t) {
		this.t = t;
	}
}

// TODO: Check for incorrect paramater count and so on.

T foo(T)(S!T s) {
	return s.t;
}

U bar(T : S!U, U)(T s) {
	return s.t;
}

U flib(alias T, U)(T!U s) {
	return s.t;
}

auto qux(uint N)(uint[N] a) {
	return N;
}

auto buzz(T)(T[10] a) {
	return uint(T.sizeof);
}

int main() {
	uint[10] a;
	auto s = S!int(13);
	return foo(s) + bar(s) + flib(s) + buzz(a) + qux(a);
}
