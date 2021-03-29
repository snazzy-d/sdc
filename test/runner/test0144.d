//T compiles:yes
//T has-passed:yes
//T retval:123
// Scope exit with loops, break and continues.

int main() {
	uint a;
	for (int i = 0; i < 5; i++) {
		assert(a == i);

		scope(exit) a++;
		assert(a == i);

		a = i;
		assert(a == i);
	}

	assert(a == 5);

	while (true) {
		scope(exit) a = 23;
		break;
	}

	assert(a == 23);

	do {
		scope(exit) a--;

		if (a > 10)
			continue;
		break;
	} while (true);

	assert(a == 9);

	while (true)
		scope(exit) return 123;

	assert(0, "unreachable");
}
