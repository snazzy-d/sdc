module source.swar.dec;

/**
 * Check we have enough digits in front of us to use SWAR.
 */
bool startsWith8DecDigits(string s, ref ulong state) {
	import source.swar.util;
	auto v = read!ulong(s);

	// Set the high bit if the character isn't between '0' and '9'.
	auto lessThan0 = v - 0x3030303030303030;
	auto moreThan9 = v + 0x4646464646464646;

	// Combine
	auto c = lessThan0 | moreThan9;

	// Check that none of the high bits are set.
	state = c & 0x8080808080808080;
	return state == 0;
}

bool hasMoreDigits(ulong state) {
	return (state & 0x80) == 0;
}

uint getDigitCount(ulong state)
		in(state != 0 && (state & 0x8080808080808080) == state) {
	import core.bitop, util.math;
	return bsf(mulhi(state, 0x0204081020408100));
}

unittest {
	static check(string s, uint count) {
		ulong state;
		if (startsWith8DecDigits(s, state)) {
			assert(count >= 8);
		} else {
			assert(hasMoreDigits(state) == (count > 0));
			assert(getDigitCount(state) == count);
		}
	}

	check("", 0);

	// Test all combinations of 2 characters.
	foreach (char c0; 0 .. 256) {
		immutable char[1] s0 = [c0];

		import source.util.ascii;
		auto isC0Dec = isDecDigit(c0);

		check(s0[], isC0Dec);

		foreach (char c1; 0 .. 256) {
			immutable char[2] s1 = [c0, c1];
			auto isC1Dec = isDecDigit(c1);

			check(s1[], isC0Dec + (isC0Dec && isC1Dec));

			static immutable char[] Chars = ['0', '9'];
			foreach (char c3; Chars) {
				foreach (char c4; Chars) {
					immutable char[4] s2 = [c0, c1, c3, c4];
					check(s2[], isC0Dec + 3 * (isC0Dec && isC1Dec));

					immutable char[4] s3 = [c4, c3, c1, c0];
					check(s3[], 2 + isC1Dec + (isC0Dec && isC1Dec));

					immutable char[8] s4 = [c0, c1, c0, c1, c0, c1, c3, c4];
					check(s4[], isC0Dec + 7 * (isC0Dec && isC1Dec));

					immutable char[8] s5 = [c4, c3, c3, c4, c3, c4, c1, c0];
					check(s5[], 6 + isC1Dec + (isC0Dec && isC1Dec));
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
	import source.swar.util;
	auto v = unalignedLoad!T(s);

	/**
	 * We could simply go for
	 *     return v & cast(T) 0x0f0f0f0f0f0f0f0f;
	 * but this form is prefered as the computation is
	 * already done in startsWith8DecDigits.
	 */
	return v - cast(T) 0x3030303030303030;
}

ubyte decodeDecDigits(T : ubyte)(string s) in(s.length >= 2) {
	uint v = loadBuffer!ushort(s);
	v = (2561 * v) >> 8;
	return v & 0xff;
}

unittest {
	foreach (s, v; ["00": 0, "09": 9, "10": 10, "28": 28, "42": 42, "56": 56,
	                "73": 73, "99": 99]) {
		ulong state;
		assert(!startsWith8DecDigits(s, state), s);
		assert(hasMoreDigits(state));
		assert(getDigitCount(state) == 2, s);
		assert(decodeDecDigits!ubyte(s) == v, s);
	}
}

ushort decodeDecDigits(T : ushort)(string s) in(s.length >= 4) {
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
		ulong state;
		assert(!startsWith8DecDigits(s, state), s);
		assert(hasMoreDigits(state));
		assert(getDigitCount(state) == 4, s);
		assert(decodeDecDigits!ushort(s) == v, s);
	}
}

private uint reduceValue(ulong v) {
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

uint decodeDecDigits(T : uint)(string s) in(s.length >= 8) {
	auto v = loadBuffer!ulong(s);
	return reduceValue(v);
}

unittest {
	foreach (s, v;
		["00000000": 0, "01234567": 1234567, "10000019": 10000019,
		 "34567890": 34567890, "52350178": 52350178, "99999999": 99999999]) {
		ulong state;
		assert(startsWith8DecDigits(s, state), s);
		assert(decodeDecDigits!uint(s) == v, s);
	}
}

uint decodeDecDigits(string s, uint count)
		in(count < 8 && count > 0 && s.length >= count) {
	import source.swar.util;
	auto v = read!ulong(s);

	v <<= (64 - 8 * count);
	v &= 0x0f0f0f0f0f0f0f0f;

	return reduceValue(v);
}

unittest {
	foreach (s, v; ["0000a000": 0, "0123456!": 123456, "100000": 100000,
	                "345678^!": 345678, "523501": 523501, "9999999": 9999999]) {
		ulong state;
		assert(!startsWith8DecDigits(s, state), s);
		assert(hasMoreDigits(state));
		assert(decodeDecDigits(s, getDigitCount(state)) == v, s);
	}
}
