module source.swar.pct;

/**
 * Check we have enough digits in front of us to use SWAR.
 */
bool startsWith8OctDigits(string s, ref ulong state) {
	import source.swar.util;
	auto v = read!ulong(s);

	// Set the high bit if the character isn't between '0' and '7'.
	auto lessThan0 = v - 0x3030303030303030;
	auto moreThan7 = v + 0x4848484848484848;

	// Combine
	auto c = lessThan0 | moreThan7;

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
		if (startsWith8OctDigits(s, state)) {
			assert(count >= 8);
		} else {
			assert(hasMoreDigits(state) == (count > 0));
			assert(getDigitCount(state) == count);
		}
	}

	check("", 0);

	static bool isOctChar(char c) {
		return '0' <= c && c <= '7';
	}

	// Test all combinations of 2 characters.
	foreach (char c0; 0 .. 256) {
		immutable char[1] s0 = [c0];
		auto isC0Oct = isOctChar(c0);

		check(s0[], isC0Oct);

		foreach (char c1; 0 .. 256) {
			immutable char[2] s1 = [c0, c1];
			auto isC1Oct = isOctChar(c1);

			check(s1[], isC0Oct + (isC0Oct && isC1Oct));

			static immutable char[] Chars = ['0', '7'];
			foreach (char c3; Chars) {
				foreach (char c4; Chars) {
					immutable char[4] s2 = [c0, c1, c3, c4];
					check(s2[], isC0Oct + 3 * (isC0Oct && isC1Oct));

					immutable char[4] s3 = [c4, c3, c1, c0];
					check(s3[], 2 + isC1Oct + (isC0Oct && isC1Oct));

					immutable char[8] s4 = [c0, c1, c0, c1, c0, c1, c3, c4];
					check(s4[], isC0Oct + 7 * (isC0Oct && isC1Oct));

					immutable char[8] s5 = [c4, c3, c3, c4, c3, c4, c1, c0];
					check(s5[], 6 + isC1Oct + (isC0Oct && isC1Oct));
				}
			}
		}
	}
}

/**
 * Parse octal numbers using SWAR.
 */
private auto loadBuffer(T)(string s) in(s.length >= T.sizeof) {
	import source.swar.util;
	auto v = unalignedLoad!T(s);

	/**
	 * We could simply go for
	 *     return v & cast(T) 0x0707070707070707;
	 * but this form is prefered as the computation is
	 * already done in startsWith8OctDigits.
	 */
	return v - cast(T) 0x3030303030303030;
}

ubyte decodeOctDigits(T : ubyte)(string s) in(s.length >= 2) {
	auto v = loadBuffer!ushort(s);
	return ((v << 3) | (v >> 8)) & 0xff;
}

unittest {
	foreach (s, v; ["00": 0, "07": 7, "10": 8, "26": 22, "42": 34, "56": 46,
	                "73": 59, "77": 63]) {
		ulong state;
		assert(!startsWith8OctDigits(s, state), s);
		assert(hasMoreDigits(state));
		assert(getDigitCount(state) == 2, s);
		assert(decodeOctDigits!ubyte(s) == v, s);
	}
}

ushort decodeOctDigits(T : ushort)(string s) in(s.length >= 4) {
	// v = [a, b, c, d]
	auto v = loadBuffer!uint(s);

	// v = [ba, dc]
	v |= v << 11;
	v &= 0x3f003f00;

	// dcba
	return ((v >> 2) | (v >> 24)) & 0xffff;
}

unittest {
	foreach (s, v; ["0000": 0, "0123": 83, "4567": 2423, "5040": 2592,
	                "6701": 3521, "7777": 4095]) {
		ulong state;
		assert(!startsWith8OctDigits(s, state), s);
		assert(hasMoreDigits(state));
		assert(getDigitCount(state) == 4, s);
		assert(decodeOctDigits!ushort(s) == v, s);
	}
}

private uint reduceValue(ulong v) {
	// v = [ba, dc, fe, hg]
	v |= v << 11;

	// a = [fe00ba, fe]
	auto a = (v >> 24) & 0x0000003f0000003f;
	a |= a << 44;

	// b = [hg00dc00, hg00]
	auto b = (v >> 2) & 0x00000fc000000fc0;
	b |= b << 44;

	// hgfedcba
	return (a | b) >> 32;
}

uint decodeOctDigits(T : uint)(string s) in(s.length >= 8) {
	auto v = loadBuffer!ulong(s);
	return reduceValue(v);
}

unittest {
	foreach (s, v;
		["00000000": 0, "01234567": 342391, "10000017": 2097167,
		 "12345670": 2739128, "52350167": 11128951, "77777777": 16777215]) {
		ulong state;
		assert(startsWith8OctDigits(s, state), s);
		assert(decodeOctDigits!uint(s) == v, s);
	}
}

uint decodeOctDigits(string s, uint count)
		in(count < 8 && count > 0 && s.length >= count) {
	import source.swar.util;
	auto v = read!ulong(s);

	v <<= (64 - 8 * count);
	v &= 0x0707070707070707;

	return reduceValue(v);
}

unittest {
	foreach (s, v; ["0000a000": 0, "0123456!": 42798, "100000": 32768,
	                "345678^!": 14711, "523501": 173889, "7777777": 2097151]) {
		ulong state;
		assert(!startsWith8OctDigits(s, state), s);
		assert(hasMoreDigits(state));
		assert(decodeOctDigits(s, getDigitCount(state)) == v, s);
	}
}
