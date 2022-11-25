module source.swar.newline;

/**
 * Check if we can skip over the next N character when
 * searching for the end of line.
 */
bool canSkipOverLine(uint N)(string s) {
	import std.format;
	static assert(
		N == 2 || N == 4 || N == 8,
		format!"canSkipOverLine only supports size 2, 4 and 8, not %d."(N)
	);

	if (s.length < N) {
		return false;
	}

	import std.meta;
	alias T = AliasSeq!(ushort, uint, ulong)[N / 4];

	import source.swar.util;
	auto v = read!T(s);

	enum T Mask = 0x8080808080808080 & T.max;

	// Clear the high bits so we can avoid spill over.
	auto ascii = (v ^ Mask) & Mask;
	auto utf8 = v & Mask;
	v &= ~Mask;

	// Set the high bit from '\n' to '\r'.
	auto lessThanCR = (cast(T) 0x8d8d8d8d8d8d8d8d) - v;
	auto moreThanLF = v + cast(T) 0x7676767676767676;
	auto combined0 = lessThanCR & moreThanLF & ascii;

	// Set high bit for utf-8 ranges c2 and e2.
	v |= cast(T) 0x2020202020202020;
	auto lessThanE2 = (cast(T) 0xe2e2e2e2e2e2e2e2) - v;
	auto moreThanE2 = v + cast(T) 0x1e1e1e1e1e1e1e1e;
	auto combined1 = lessThanE2 & moreThanE2 & utf8;

	return (combined0 | combined1) == 0;
}

unittest {
	static check0(string s) {
		assert(!canSkipOverLine!2(s), s);
		assert(!canSkipOverLine!4(s), s);
		assert(!canSkipOverLine!8(s), s);
	}

	static check2(string s) {
		assert(canSkipOverLine!2(s), s);
		assert(!canSkipOverLine!4(s), s);
		assert(!canSkipOverLine!8(s), s);
	}

	static check4(string s) {
		assert(canSkipOverLine!2(s), s);
		assert(canSkipOverLine!4(s), s);
		assert(!canSkipOverLine!8(s), s);
	}

	static check8(string s) {
		assert(canSkipOverLine!2(s), s);
		assert(canSkipOverLine!4(s), s);
		assert(canSkipOverLine!8(s), s);
	}

	static mayIndicateLineBreak(char c) {
		switch (c) {
			case '\n', '\f', '\v', '\r', 0xc2, 0xe2:
				return true;

			default:
				return false;
		}
	}

	check0("");

	// Test all combinations of 2 characters.
	foreach (char c0; 0 .. 256) {
		immutable char[1] s0 = [c0];

		check0(s0[]);

		bool c0nl = mayIndicateLineBreak(c0);
		foreach (char c1; 0 .. 256) {
			immutable char[2] s1 = [c0, c1];

			bool c1nl = mayIndicateLineBreak(c1);
			if (c0nl || c1nl) {
				check0(s1[]);
			} else {
				check2(s1[]);
			}

			static immutable char[] Chars =
				['\n' - 1, '\r' + 1, '\n' | 0x80, '\r' | 0x80, 0xc1, 0xc3, 0x42,
				 0xe1, 0xe3, 0x62];
			foreach (char c3; Chars) {
				foreach (char c4; Chars) {
					immutable char[4] s2 = [c0, c1, c3, c4];
					immutable char[4] s3 = [c4, c3, c1, c0];

					immutable char[8] s4 = [c0, c1, c0, c1, c0, c1, c3, c4];
					immutable char[8] s5 = [c4, c3, c3, c4, c3, c4, c1, c0];

					if (c0nl || c1nl) {
						check0(s2[]);
						check2(s3[]);
						check0(s4[]);
						check4(s5[]);
					} else {
						check4(s2[]);
						check4(s3[]);
						check8(s4[]);
						check8(s5[]);
					}
				}
			}
		}
	}
}
