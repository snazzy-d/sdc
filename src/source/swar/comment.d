module source.swar.comment;

/**
 * Check if we can skip over the next N character when
 * searching for the end of a comment.
 */
bool canSkipOverComment(uint N)(string s, ref uint state) {
	import std.format;
	static assert(
		N == 2 || N == 4 || N == 8,
		format!"canSkipOverComment only supports size 2, 4 and 8, not %d."(N)
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
	v &= ~Mask;

	// Set the high bit on '/'.
	auto lessThanSlash = (cast(T) 0xafafafafafafafaf) - v;
	auto moreThanSlash = v + cast(T) 0x5151515151515151;
	auto combinedSlash = lessThanSlash & moreThanSlash & ascii;

	// Set the high bit on '*'.
	auto lessThanStar = (cast(T) 0xaaaaaaaaaaaaaaaa) - v;
	auto moreThanStar = v + cast(T) 0x5656565656565656;
	auto combinedStar = lessThanStar & moreThanStar & ascii;
	auto shiftedStar = (combinedStar << 8) | state;

	enum S1 = 8 * (N - 1);
	state = combinedStar >> S1;
	return (combinedSlash & shiftedStar) == 0;
}

char getPreviousCharFromState(uint state) {
	return ('*' | 0x80) ^ (state & 0xff);
}

unittest {
	assert(getPreviousCharFromState(0) != '*');
	assert(getPreviousCharFromState(0x80) == '*');
}

unittest {
	static bool testSkip(uint N)(string s, char previous = '\0') {
		uint state = (previous == '*') ? 0x80 : 0x00;
		auto r = canSkipOverComment!N(s, state);

		assert(!r || state == (s[N - 1] == '*' ? 0x80 : 0x00));
		return r;
	}

	static check0(string s, char previous = '\0') {
		assert(!testSkip!2(s, previous), s);
		assert(!testSkip!4(s, previous), s);
		assert(!testSkip!8(s, previous), s);
	}

	static check2(string s, char previous = '\0') {
		assert(testSkip!2(s, previous), s);
		assert(!testSkip!4(s, previous), s);
		assert(!testSkip!8(s, previous), s);
	}

	static check4(string s, char previous = '\0') {
		assert(testSkip!2(s, previous), s);
		assert(testSkip!4(s, previous), s);
		assert(!testSkip!8(s, previous), s);
	}

	static check8(string s, char previous = '\0') {
		assert(testSkip!2(s, previous), s);
		assert(testSkip!4(s, previous), s);
		assert(testSkip!8(s, previous), s);
	}

	// Some cases that proved problematic during testing.
	check0("*/");
	check2("/*");
	check0("/*", '*');
	check2("\xaa/");
	check4("\x29\xff\x29/");
	check4("\xff\x29/\x29");
	check2(")*/)");

	// Test all combinations of 2 characters.
	foreach (char c0; 0 .. 256) {
		immutable char[1] s0 = [c0];

		check0("", c0);
		check0(s0[]);

		foreach (char c1; 0 .. 256) {
			immutable char[2] s1 = [c0, c1];

			check0(s0[], c1);

			if (s1 == "*/") {
				check0(s1[]);
			} else if (c0 == '/') {
				check0(s1[], '*');
				check2(s1[]);
			} else {
				check2(s1[], '*');
				check2(s1[]);
			}

			static immutable char[] Chars =
				['*' - 1, '*' + 1, '*' | 0x80, '/' - 1, '/' + 1, '/' | 0x80,
				 '\0', 0x80, '\xff'];
			foreach (char c3; Chars) {
				foreach (char c4; Chars) {
					immutable char[4] s2 = [c0, c1, c3, c4];
					immutable char[4] s3 = [c3, c0, c1, c4];
					immutable char[4] s4 = [c3, c4, c0, c1];

					immutable char[8] s5 = [c0, c1, c3, c4, c0, c1, c3, c4];
					immutable char[8] s6 = [c3, c4, c0, c1, c3, c4, c3, c4];
					immutable char[8] s7 = [c3, c4, c3, c0, c1, c4, c3, c4];
					immutable char[8] s8 = [c3, c4, c3, c4, c3, c4, c0, c1];

					if (s1 == "*/") {
						check0(s2[]);
						check2(s3[]);
						check2(s4[]);
						check0(s5[]);
						check2(s6[]);
						check4(s7[]);
						check4(s7[4 .. 8]);
						check0(s7[4 .. 8], c0);
						check4(s8[]);
					} else {
						check4(s2[]);
						check4(s3[]);
						check4(s4[]);
						check8(s5[]);
						check8(s6[]);
						check8(s7[]);
						check4(s7[4 .. 8]);
						check4(s7[4 .. 8], c0);
						check8(s8[]);
					}
				}
			}
		}
	}
}

/**
 * Check if we can skip over the next N character when
 * searching for the end of a comment.
 */
bool canSkipOverNestedComment(uint N)(string s, ref uint state1,
                                      ref uint state2) {
	import std.format;
	static assert(
		N == 2 || N == 4 || N == 8,
		format!"canSkipOverNestedComment only supports size 2, 4 and 8, not %d."(
			N)
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
	v &= ~Mask;

	// Set the high bit on '/'.
	auto lessThanSlash = (cast(T) 0xafafafafafafafaf) - v;
	auto moreThanSlash = v + cast(T) 0x5151515151515151;
	auto combinedSlash = lessThanSlash & moreThanSlash & ascii;
	auto shiftedSlash = (combinedSlash << 8) | state1;

	// Set the high bit on '+'.
	auto lessThanPlus = (cast(T) 0xabababababababab) - v;
	auto moreThanPlus = v + cast(T) 0x5555555555555555;
	auto combinedPlus = lessThanPlus & moreThanPlus & ascii;
	auto shiftedPlus = (combinedPlus << 8) | state2;

	enum S1 = 8 * (N - 1);
	state1 = combinedSlash >> S1;
	state2 = combinedPlus >> S1;
	return ((combinedSlash & shiftedPlus) | (combinedPlus & shiftedSlash)) == 0;
}

char getPreviousCharFromNestedState(uint state1, uint state2) {
	char base = ('+' | 0x80) ^ ((state1 | state2) & 0xff);
	return base + (state1 >> 5) & 0xff;
}

unittest {
	assert(getPreviousCharFromNestedState(0, 0) != '+');
	assert(getPreviousCharFromNestedState(0, 0) != '/');
	assert(getPreviousCharFromNestedState(0x80, 0) == '/');
	assert(getPreviousCharFromNestedState(0, 0x80) == '+');
}

unittest {
	static bool testSkip(uint N)(string s, char previous = '\0') {
		uint state1 = (previous == '/') ? 0x80 : 0x00;
		uint state2 = (previous == '+') ? 0x80 : 0x00;
		auto r = canSkipOverNestedComment!N(s, state1, state2);

		assert(!r || state1 == (s[N - 1] == '/' ? 0x80 : 0x00));
		assert(!r || state2 == (s[N - 1] == '+' ? 0x80 : 0x00));
		return r;
	}

	static check0(string s, char previous = '\0') {
		assert(!testSkip!2(s, previous), s);
		assert(!testSkip!4(s, previous), s);
		assert(!testSkip!8(s, previous), s);
	}

	static check2(string s, char previous = '\0') {
		assert(testSkip!2(s, previous), s);
		assert(!testSkip!4(s, previous), s);
		assert(!testSkip!8(s, previous), s);
	}

	static check4(string s, char previous = '\0') {
		assert(testSkip!2(s, previous), s);
		assert(testSkip!4(s, previous), s);
		assert(!testSkip!8(s, previous), s);
	}

	static check8(string s, char previous = '\0') {
		assert(testSkip!2(s, previous), s);
		assert(testSkip!4(s, previous), s);
		assert(testSkip!8(s, previous), s);
	}

	// Some cases that proved problematic during testing.
	check0("+/");
	check0("/+");
	check0("//", '+');
	check0("++", '/');
	check2("\xaa/");
	check4("\x2a\xff\x2a/");
	check4("\xff\x2a/\x2a");
	check2("*+/*");

	// Test all combinations of 2 characters.
	foreach (char c0; 0 .. 256) {
		immutable char[1] s0 = [c0];

		check0("", c0);
		check0(s0[]);

		foreach (char c1; 0 .. 256) {
			immutable char[2] s1 = [c0, c1];

			check0(s0[], c1);

			if (s1 == "/+" || s1 == "+/") {
				check0(s1[]);
			} else if (c0 == '/') {
				check0(s1[], '+');
				check2(s1[]);
			} else if (c0 == '+') {
				check0(s1[], '/');
				check2(s1[]);
			} else {
				check2(s1[], '/');
				check2(s1[], '+');
				check2(s1[]);
			}

			static immutable char[] Chars =
				['+' - 1, '+' + 1, '+' | 0x80, '/' - 1, '/' + 1, '/' | 0x80,
				 '\0', 0x80, '\xff'];
			foreach (char c3; Chars) {
				foreach (char c4; Chars) {
					immutable char[4] s2 = [c0, c1, c3, c4];
					immutable char[4] s3 = [c3, c0, c1, c4];
					immutable char[4] s4 = [c3, c4, c0, c1];

					immutable char[8] s5 = [c0, c1, c3, c4, c0, c1, c3, c4];
					immutable char[8] s6 = [c3, c4, c0, c1, c3, c4, c3, c4];
					immutable char[8] s7 = [c3, c4, c3, c0, c1, c4, c3, c4];
					immutable char[8] s8 = [c3, c4, c3, c4, c3, c4, c0, c1];

					if (s1 == "/+" || s1 == "+/") {
						check0(s2[]);
						check2(s3[]);
						check2(s4[]);
						check0(s5[]);
						check2(s6[]);
						check4(s7[]);
						check4(s7[4 .. 8]);
						check0(s7[4 .. 8], c0);
						check4(s8[]);
					} else {
						check4(s2[]);
						check4(s3[]);
						check4(s4[]);
						check8(s5[]);
						check8(s6[]);
						check8(s7[]);
						check4(s7[4 .. 8]);
						check4(s7[4 .. 8], c0);
						check8(s8[]);
					}
				}
			}
		}
	}
}
