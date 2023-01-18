module source.swar.newline;

/**
 * Check if we can skip over the next N character when
 * searching for the end of line.
 */
bool canSkipOver8CharsInLine(string s, ref ulong state) {
	import source.swar.util;
	auto v = read!ulong(s);

	if (s.length < 8) {
		// Pad with line feed so we don't skip past
		// the end of the input.
		v |= 0x0a0a0a0a0a0a0a0a << (8 * s.length);
	}

	enum MSBs = 0x8080808080808080;

	// Clear the high bits so we can avoid spill over.
	auto ascii = (v ^ MSBs) & MSBs;
	auto utf8 = v & MSBs;
	v &= ~MSBs;

	// Set the high bit from '\n' to '\r'.
	auto lessThanCR = 0x8d8d8d8d8d8d8d8d - v;
	auto moreThanLF = v + 0x7676767676767676;
	auto combined0 = lessThanCR & moreThanLF & ascii;

	// Set high bit for utf-8 ranges c2 and e2.
	v |= 0x2020202020202020;
	auto lessThanE2 = 0xe2e2e2e2e2e2e2e2 - v;
	auto moreThanE2 = v + 0x1e1e1e1e1e1e1e1e;
	auto combined1 = lessThanE2 & moreThanE2 & utf8;

	state = combined0 | combined1;
	return state == 0;
}

uint getSkippableCharsCount(ulong state)
		in(state != 0 && (state & 0x8080808080808080) == state) {
	import core.bitop, util.math;
	return bsf(mulhi(state, 0x0204081020408100));
}

unittest {
	static check(string s, uint count) {
		ulong state;
		if (canSkipOver8CharsInLine(s, state)) {
			assert(count >= 8);
		} else {
			assert(getSkippableCharsCount(state) == count);
		}
	}

	static mayIndicateLineBreak(char c) {
		switch (c) {
			case '\n', '\f', '\v', '\r', 0xc2, 0xe2:
				return true;

			default:
				return false;
		}
	}

	check("", 0);

	// Test all combinations of 2 characters.
	foreach (char c0; 0 .. 256) {
		immutable char[1] s0 = [c0];
		bool c0nl = mayIndicateLineBreak(c0);

		check(s0[], !c0nl);

		foreach (char c1; 0 .. 256) {
			immutable char[2] s1 = [c0, c1];
			bool c1nl = mayIndicateLineBreak(c1);

			check(s1[], !c0nl + !(c0nl || c1nl));

			static immutable char[] Chars =
				['\n' - 1, '\r' + 1, '\n' | 0x80, '\r' | 0x80, 0xc1, 0xc3, 0x42,
				 0xe1, 0xe3, 0x62];
			foreach (char c3; Chars) {
				foreach (char c4; Chars) {
					immutable char[4] s2 = [c0, c1, c3, c4];
					check(s2[], !c0nl + 3 * !(c0nl || c1nl));

					immutable char[4] s3 = [c4, c3, c1, c0];
					check(s3[], 2 + !c1nl + !(c0nl || c1nl));

					immutable char[8] s4 = [c0, c1, c0, c1, c0, c1, c3, c4];
					check(s4[], !c0nl + 7 * !(c0nl || c1nl));

					immutable char[8] s5 = [c4, c3, c3, c4, c3, c4, c1, c0];
					check(s5[], 6 + !c1nl + !(c0nl || c1nl));
				}
			}
		}
	}
}
