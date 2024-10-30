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
