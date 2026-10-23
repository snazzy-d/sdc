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

unittest labeled_break_only_exit {
	uint k;
	Outer: while (true) {
		foreach (i; 0 .. 42) {
			k = i;
			if (i > 3) {
				break Outer;
			}
		}
	}

	assert(k == 4);
}

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

unittest foreach_array {
	int[4] a = [1, 2, 3, 4];

	int acc;
	foreach (i, e; a) {
		acc = acc * 10 + e;
		assert(e == i + 1);
	}

	assert(acc == 1234);

	foreach (ref e; a) {
		e *= 2;
	}

	assert(a[0] == 2 && a[3] == 8);
}

unittest foreach_literal {
	// The index is mutable, even though the literal is immutable.
	uint n;
	foreach (c; "test") {
		n++;
	}

	assert(n == 4);

	foreach (i, c; "test") {
		assert("test"[i] == c);
		i = 3;
	}
}

unittest foreach_index_type {
	int[4] a = [10, 11, 12, 13];
	int[] s = a[0 .. a.length];

	// The index is a size_t, unless declared otherwise.
	uint n;
	foreach (i, e; a) {
		size_t si = i;
		assert(a[si] == e);
		n++;
	}

	foreach (ulong i, e; s) {
		assert(e == 10 + i);
		n++;
	}

	foreach_reverse (ubyte i, e; a) {
		assert(e == 10 + i);
		n++;
	}

	foreach_reverse (long i, e; s) {
		assert(e == 10 + i);
		n++;
	}

	assert(n == 16);

	// A narrower index can be used if it can count up to the length.
	int[255] b;
	foreach (int i, ref e; b) {
		e = i;
	}

	n = 0;
	foreach (ubyte i, e; b) {
		assert(i == e);
		n++;
	}

	assert(n == 255);
}

unittest foreach_reverse_array {
	int[4] a = [1, 2, 3, 4];

	int acc;
	foreach_reverse (i, e; a) {
		acc = acc * 10 + e;
		assert(e == i + 1);
	}

	assert(acc == 4321);

	foreach_reverse (ref e; a) {
		e *= 2;
	}

	assert(a[0] == 2 && a[3] == 8);
}

unittest foreach_slice {
	int[] s = [1, 2, 3, 4];

	int acc;
	foreach (e; s) {
		acc = acc * 10 + e;
	}

	assert(acc == 1234);

	size_t indices;
	foreach (i, ref e; s) {
		e += 10;
		indices = indices * 10 + i;
	}

	assert(indices == 123);
	assert(s[0] == 11 && s[3] == 14);

	int[] empty;
	foreach (e; empty) {
		assert(0);
	}
}

unittest foreach_reverse_slice {
	int[] s = [1, 2, 3, 4];

	int acc;
	foreach_reverse (e; s) {
		acc = acc * 10 + e;
	}

	assert(acc == 4321);

	size_t indices;
	foreach_reverse (i, ref e; s) {
		e += 10;
		indices = indices * 10 + i;
	}

	assert(indices == 3210);
	assert(s[0] == 11 && s[3] == 14);

	int[] empty;
	foreach_reverse (e; empty) {
		assert(0);
	}
}
