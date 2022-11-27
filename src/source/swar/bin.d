module source.swar.bin;

/**
 * Check we have enough digits in front of us to use SWAR.
 */
bool startsWithBinDigits(uint N)(string s) {
	import std.format;
	static assert(
		N == 2 || N == 4 || N == 8,
		format!"startsWithBinDigits only supports size 2, 4 and 8, not %d."(N)
	);

	if (s.length < N) {
		return false;
	}

	import std.meta;
	alias T = AliasSeq!(ushort, uint, ulong)[N / 4];

	import source.swar.util;
	auto v = read!T(s);

	// If the input is valid, make it all '1's.
	auto allOnes = v | cast(T) 0x0101010101010101;
	return allOnes == cast(T) 0x3131313131313131;
}

unittest {
	static check0(string s) {
		assert(!startsWithBinDigits!2(s), s);
		assert(!startsWithBinDigits!4(s), s);
		assert(!startsWithBinDigits!8(s), s);
	}

	static check2(string s) {
		assert(startsWithBinDigits!2(s), s);
		assert(!startsWithBinDigits!4(s), s);
		assert(!startsWithBinDigits!8(s), s);
	}

	static check4(string s) {
		assert(startsWithBinDigits!2(s), s);
		assert(startsWithBinDigits!4(s), s);
		assert(!startsWithBinDigits!8(s), s);
	}

	static check8(string s) {
		assert(startsWithBinDigits!2(s), s);
		assert(startsWithBinDigits!4(s), s);
		assert(startsWithBinDigits!8(s), s);
	}

	check0("");

	static bool isBinChar(char c) {
		return c == '0' || c == '1';
	}

	// Test all combinations of 2 characters.
	foreach (char c0; 0 .. 256) {
		immutable char[1] s0 = [c0];
		check0(s0[]);

		auto isC0Bin = isBinChar(c0);
		foreach (char c1; 0 .. 256) {
			immutable char[2] s1 = [c0, c1];

			auto isC1Bin = isBinChar(c1);
			if (isC0Bin && isC1Bin) {
				check2(s1[]);
			} else {
				check0(s1[]);
			}

			static immutable char[] Chars = ['0', '1'];
			foreach (char c3; Chars) {
				foreach (char c4; Chars) {
					immutable char[4] s2 = [c0, c1, c3, c4];
					immutable char[4] s3 = [c4, c3, c1, c0];

					immutable char[8] s4 = [c0, c1, c0, c1, c0, c1, c3, c4];
					immutable char[8] s5 = [c4, c3, c3, c4, c3, c4, c1, c0];

					if (isC0Bin && isC1Bin) {
						check4(s2[]);
						check4(s3[]);
						check8(s4[]);
						check8(s5[]);
					} else {
						check0(s2[]);
						check2(s3[]);
						check0(s4[]);
						check4(s5[]);
					}
				}
			}
		}
	}
}

/**
 * Parse binary numbers using SWAR.
 */
ubyte parseBinDigits(T : ubyte)(string s) in(s.length >= 8) {
	auto v = *(cast(ulong*) s.ptr);
	v &= 0x0101010101010101;
	v *= 0x8040201008040201;
	return v >> 56;
}

unittest {
	foreach (s, v;
		["00000000": 0x00, "01001001": 0x49, "01010101": 0x55, "10101010": 0xaa,
		 "11000000": 0xc0, "11011011": 0xdb, "11111111": 0xff]) {
		assert(startsWithBinDigits!8(s), s);
		assert(parseBinDigits!ubyte(s) == v, s);
	}
}
