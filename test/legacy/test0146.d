//T compiles:yes
//T retval:0
//T has-passed:yes
// Tests pointer casts.

struct S {
	uint value;
}

int main() {
	S s;
	s.value = 123;

	auto ptr = cast(uint*) &s;
	assert(*ptr == 123);

	return 0;
}
