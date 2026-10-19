unittest labeled_break_switch {
	uint k;
	Sw: switch (k) {
		default:
			foreach (i; 0 .. 42) {
				k = i;
				if (i > 3) {
					break Sw;
				}
			}

			assert(0);
	}

	assert(k == 4);
}
