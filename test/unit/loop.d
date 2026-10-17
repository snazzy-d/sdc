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
