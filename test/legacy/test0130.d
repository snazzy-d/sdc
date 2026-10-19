//T compiles:yes
//T has-passed:yes
//T retval:56
// Test IFTI with explicit parameter and conversion.

int foo()(int i) {
	return i + cast(int) bar!long(i);
}

auto bar(T)(T t) {
	return T.sizeof + buzz(&t) + t;
}

auto buzz(T)(T* t) {
	return (*t)++;
}

auto qux(T : U*, U)(T t) {
	return buzz(t) + *t + U.sizeof;
}

int main() {
	int a = 5;

	return cast(int) (buzz(&a) + foo(a) + bar(1) + qux(&a));
}
