unittest labeled_continue {
	uint k, m;
	Outer: foreach (i; 0 .. 42) {
		k = i;
		foreach (j; 0 .. 42) {
			if (k > 3) {
				continue Outer;
			}

			m++;
		}
	}

	assert(k == 41);
	assert(m == 168);
}

/*
unittest labeled_break {
	uint k;
	Outer: foreach (i; 0 .. 42) {
		k = i;
		foreach (j; 0 .. 42) {
			if (i > 3) {
				break Outer;
			}
		}
	}

	assert(k == 4);
}
// */

unittest foreach_ref_qualifier_conversion {
	// A qualifier change that is only read through binds by ref.
	int[] arr = [1, 2, 3];
	foreach (i, ref const int e; arr) {
		arr[i] = 42;
		assert(e == 42);
	}
}

unittest foreach_value_conversion {
	// A conversion that is only valid by value.
	const(int[])[] arr = [[1, 2], [3]];
	int sum;
	foreach (const(int)[] e; arr) {
		sum += e[0];
	}

	assert(sum == 4);
}

unittest scope_exit_loops {
	// Scope guards run at the end of each iteration.
	uint a;
	for (int i = 0; i < 5; i++) {
		assert(a == i);

		scope(exit) a++;
		assert(a == i);

		a = i;
		assert(a == i);
	}

	assert(a == 5);
}

unittest scope_exit_break {
	// Scope guards run when breaking out of the loop.
	uint a;
	while (true) {
		scope(exit) a = 23;
		break;
	}

	assert(a == 23);
}

unittest scope_exit_continue {
	// Scope guards run when continuing the loop.
	uint a = 23;
	do {
		scope(exit) a--;

		if (a > 10) {
			continue;
		}

		break;
	} while (true);

	assert(a == 9);
}

int scopeExitReturn() {
	while (true) {
		scope(exit) return 123;
	}
}

unittest scope_exit_return {
	// A scope guard can return out of an infinite loop.
	assert(scopeExitReturn() == 123);
}
