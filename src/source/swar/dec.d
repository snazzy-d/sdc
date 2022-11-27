module source.swar.dec;

/**
 * Check we have enough digits in front of us to use SWAR.
 */
bool startsWithDecDigits(uint N)(string s) {
	import std.format;
	static assert(
		N == 2 || N == 4 || N == 8,
		format!"startsWithDecDigits only supports size 2, 4 and 8, not %d."(N)
	);

	if (s.length < N) {
		return false;
	}

	import std.meta;
	alias T = AliasSeq!(ushort, uint, ulong)[N / 4];

	import source.swar.util;
	auto v = read!T(s);

	// Set the high bit if the character isn't between '0' and '9'.
	auto lessThan0 = v - cast(T) 0x3030303030303030;
	auto moreThan9 = v + cast(T) 0x4646464646464646;

	// Combine
	auto c = lessThan0 | moreThan9;

	// Check that none of the high bits are set.
	enum T Mask = 0x8080808080808080 & T.max;
	return (c & Mask) == 0;
}

unittest {
	static check0(string s) {
		assert(!startsWithDecDigits!2(s), s);
		assert(!startsWithDecDigits!4(s), s);
		assert(!startsWithDecDigits!8(s), s);
	}

	static check2(string s) {
		assert(startsWithDecDigits!2(s), s);
		assert(!startsWithDecDigits!4(s), s);
		assert(!startsWithDecDigits!8(s), s);
	}

	static check4(string s) {
		assert(startsWithDecDigits!2(s), s);
		assert(startsWithDecDigits!4(s), s);
		assert(!startsWithDecDigits!8(s), s);
	}

	static check8(string s) {
		assert(startsWithDecDigits!2(s), s);
		assert(startsWithDecDigits!4(s), s);
		assert(startsWithDecDigits!8(s), s);
	}

	check0("");

	static bool isDecChar(char c) {
		return '0' <= c && c <= '9';
	}

	// Test all combinations of 2 characters.
	foreach (char c0; 0 .. 256) {
		immutable char[1] s0 = [c0];
		check0(s0[]);

		auto isC0Dec = isDecChar(c0);
		foreach (char c1; 0 .. 256) {
			immutable char[2] s1 = [c0, c1];

			auto isC1Dec = isDecChar(c1);
			if (isC0Dec && isC1Dec) {
				check2(s1[]);
			} else {
				check0(s1[]);
			}

			static immutable char[] Chars = ['0', '9'];
			foreach (char c3; Chars) {
				foreach (char c4; Chars) {
					immutable char[4] s2 = [c0, c1, c3, c4];
					immutable char[4] s3 = [c4, c3, c1, c0];

					immutable char[8] s4 = [c0, c1, c0, c1, c0, c1, c3, c4];
					immutable char[8] s5 = [c4, c3, c3, c4, c3, c4, c1, c0];

					if (isC0Dec && isC1Dec) {
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
 * Parse decimal numbers using SWAR.
 *
 * http://0x80.pl/notesen/2014-10-12-parsing-decimal-numbers-part-1-swar.html
 * Archive: https://archive.ph/1xl45
 *
 * https://lemire.me/blog/2022/01/21/swar-explained-parsing-eight-digits/
 * Archive: https://archive.ph/of2xZ
 */
private auto loadBuffer(T)(string s) in(s.length >= T.sizeof) {
	auto v = *(cast(T*) s.ptr);

	/**
	 * We could simply go for
	 *     return v - cast(T) 0x0f0f0f0f0f0f0f0f;
	 * but this form is prefered as the computation is
	 * already done in startsWithDecDigits.
	 */
	return v - cast(T) 0x3030303030303030;
}

ubyte parseDecDigits(T : ubyte)(string s) in(s.length >= 2) {
	uint v = loadBuffer!ushort(s);
	v = (2561 * v) >> 8;
	return v & 0xff;
}

unittest {
	foreach (s, v; ["00": 0, "09": 9, "10": 10, "28": 28, "42": 42, "56": 56,
	                "73": 73, "99": 99]) {
		assert(startsWithDecDigits!2(s), s);
		assert(parseDecDigits!ubyte(s) == v, s);
	}
}

ushort parseDecDigits(T : ushort)(string s) in(s.length >= 4) {
	// v = [a, b, c, d]
	auto v = loadBuffer!uint(s);

	// v = [ba, dc]
	v = (2561 * v) >> 8;
	v &= 0x00ff00ff;

	// dcba
	v *= 6553601;
	return v >> 16;
}

unittest {
	foreach (s, v; ["0000": 0, "0123": 123, "4567": 4567, "5040": 5040,
	                "8901": 8901, "9999": 9999]) {
		assert(startsWithDecDigits!4(s), s);
		assert(parseDecDigits!ushort(s) == v, s);
	}
}

uint parseDecDigits(T : uint)(string s) in(s.length >= 8) {
	// v = [a, b, c, d, e, f, g, h]
	auto v = loadBuffer!ulong(s);

	// v = [ba, dc, fe, hg]
	v *= 2561;

	// a = [fe00ba, fe]
	auto a = (v >> 24) & 0x000000ff000000ff;
	a *= 0x0000271000000001;

	// b = [hg00dc00, hg00]
	auto b = (v >> 8) & 0x000000ff000000ff;
	b *= 0x000F424000000064;

	// hgfedcba
	return (a + b) >> 32;
}

unittest {
	foreach (s, v;
		["00000000": 0, "01234567": 1234567, "10000019": 10000019,
		 "34567890": 34567890, "52350178": 52350178, "99999999": 99999999]) {
		assert(startsWithDecDigits!8(s), s);
		assert(parseDecDigits!uint(s) == v, s);
	}
}
