module source.swar.bin;

/**
 * Check we have enough digits in front of us to use SWAR.
 */
bool startsWith8BinDigits(string s, ref ulong state) {
	import source.swar.util;
	auto v = read!ulong(s);

	// If the input is valid, make it all '1's.
	state = v | 0x0101010101010101;
	return state == 0x3131313131313131;
}

bool hasMoreDigits(ulong state) {
	return (state & 0xff) == 0x31;
}

uint getDigitCount(ulong state) in(state != 0x3131313131313131) {
	state ^= 0x3131313131313131;
	state |= state + 0x7f7f7f7f7f7f7f7f;
	state &= 0x8080808080808080;

	import core.bitop, util.math;
	return bsf(mulhi(state, 0x0204081020408100));
}

unittest {
	static check(string s, uint count) {
		ulong state;
		if (startsWith8BinDigits(s, state)) {
			assert(count >= 8);
		} else {
			assert(hasMoreDigits(state) == (count > 0));
			assert(getDigitCount(state) == count);
		}
	}

	check("", 0);
	static bool isBinChar(char c) {
		return c == '0' || c == '1';
	}

	// Test all combinations of 2 characters.
	foreach (char c0; 0 .. 256) {
		immutable char[1] s0 = [c0];
		auto isC0Bin = isBinChar(c0);

		check(s0[], isC0Bin);

		foreach (char c1; 0 .. 256) {
			immutable char[2] s1 = [c0, c1];
			auto isC1Bin = isBinChar(c1);

			check(s1[], isC0Bin + (isC0Bin && isC1Bin));

			static immutable char[] Chars = ['0', '1'];
			foreach (char c3; Chars) {
				foreach (char c4; Chars) {
					immutable char[4] s2 = [c0, c1, c3, c4];
					check(s2[], isC0Bin + 3 * (isC0Bin && isC1Bin));

					immutable char[4] s3 = [c4, c3, c1, c0];
					check(s3[], 2 + isC1Bin + (isC0Bin && isC1Bin));

					immutable char[8] s4 = [c0, c1, c0, c1, c0, c1, c3, c4];
					check(s4[], isC0Bin + 7 * (isC0Bin && isC1Bin));

					immutable char[8] s5 = [c4, c3, c3, c4, c3, c4, c1, c0];
					check(s5[], 6 + isC1Bin + (isC0Bin && isC1Bin));
				}
			}
		}
	}
}

/**
 * Parse binary numbers using SWAR.
 */
private ubyte computeValue(ulong v) {
	v &= 0x0101010101010101;
	v *= 0x8040201008040201;
	return v >> 56;
}

ubyte decodeBinDigits(string s) in(s.length >= 8) {
	import source.swar.util;
	auto v = unalignedLoad!ulong(s);
	return computeValue(v);
}

unittest {
	foreach (s, v;
		["00000000": 0x00, "01001001": 0x49, "01010101": 0x55, "10101010": 0xaa,
		 "11000000": 0xc0, "11100111": 0xe7, "11011011": 0xdb, "11111111": 0xff]
	) {
		ulong state;
		assert(startsWith8BinDigits(s, state), s);
		assert(decodeBinDigits(s) == v, s);
	}
}

ubyte decodeBinDigits(string s, uint count) in(count < 8 && s.length >= count) {
	import source.swar.util;
	auto v = read!ulong(s);

	return computeValue(v) >> (8 - count);
}

unittest {
	foreach (s, v;
		["0000a000": 0x00, "001001P0": 0x09, "1010101+": 0x55, "101010^!": 0x2a,
		 "1000011z": 0x43, "1011011": 0x5b, "1111111": 0x7f]) {
		ulong state;
		assert(!startsWith8BinDigits(s, state), s);
		assert(hasMoreDigits(state));
		assert(decodeBinDigits(s, getDigitCount(state)) == v, s);
	}
}
