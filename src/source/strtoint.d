module source.strtoint;

ulong strToInt(string s) {
	if (s.length < 3 || s[0] != '0') {
		goto ParseDec;
	}

	switch (s[1]) {
		case 'x', 'X':
			return strToHexInt(s[2 .. $]);

		case 'b', 'B':
			return strToBinInt(s[2 .. $]);

		default:
			// Break to parse as decimal.
			break;
	}

ParseDec:
	return strToDecInt(s);
}

unittest {
	assert(strToInt("") == 0);
	assert(strToInt("0") == 0);
	assert(strToInt("42") == 42);
	assert(strToInt("123") == 123);
	assert(strToInt("0x0") == 0);
	assert(strToInt("0xaa") == 170);
	assert(strToInt("0b101") == 5);
}

ulong strToDecInt(string s) {
	ulong result = 0;

	while (true) {
		ulong state;

		import source.swar.dec;
		while (startsWith8DecDigits(s, state)) {
			result *= 100000000;
			result += parseDecDigits!uint(s);
			s = s[8 .. $];
		}

		static immutable uint[8] POWERS_OF_10 =
			[1, 10, 100, 1000, 10000, 100000, 1000000, 10000000];

		auto digitCount = getDigitCount(state);
		result *= POWERS_OF_10[digitCount];
		result += parseDecDigits(s, digitCount);
		s = s[digitCount .. $];

		if (s.length > 0 && s[0] == '_') {
			s = s[1 .. $];
			continue;
		}

		return result;
	}
}

unittest {
	assert(strToDecInt("") == 0);
	assert(strToDecInt("0") == 0);
	assert(strToDecInt("42") == 42);
	assert(strToDecInt("1234567890") == 1234567890);
	assert(strToDecInt("18446744073709551615") == 18446744073709551615);
	assert(strToDecInt("34_56") == 3456);
}

ulong strToBinInt(string s) {
	ulong result = 0;

	while (true) {
		ulong state;

		import source.swar.bin;
		while (startsWith8BinDigits(s, state)) {
			result <<= 8;
			result |= parseBinDigits(s);
			s = s[8 .. $];
		}

		auto digitCount = getDigitCount(state);
		result <<= digitCount;
		result |= parseBinDigits(s, digitCount);
		s = s[digitCount .. $];

		if (s.length > 0 && s[0] == '_') {
			s = s[1 .. $];
			continue;
		}

		return result;
	}
}

unittest {
	assert(strToBinInt("") == 0);
	assert(strToBinInt("0") == 0);
	assert(strToBinInt("1010") == 10);
	assert(strToBinInt("0101010") == 42);
	assert(strToBinInt(
		"0101010101010101010101010101010101010101010101010101010101010101",
	) == 0x5555555555555555);
	assert(strToBinInt(
		"0110011001100110011001100110011001100110011001100110011001100110",
	) == 0x6666666666666666);
	assert(strToBinInt(
		"1001100110011001100110011001100110011001100110011001100110011001",
	) == 0x9999999999999999);
	assert(strToBinInt(
		"1010101010101010101010101010101010101010101010101010101010101010",
	) == 0xaaaaaaaaaaaaaaaa);
	assert(strToBinInt(
		"1111111111111111111111111111111111111111111111111111111111111111",
	) == 0xffffffffffffffff);
	assert(strToBinInt("11_101_00") == 116);
}

ulong strToHexInt(string s) {
	ulong result = 0;

	while (true) {
		ulong state;

		import source.swar.hex;
		while (startsWith8HexDigits(s, state)) {
			result <<= 32;
			result |= parseHexDigits!uint(s);
			s = s[8 .. $];
		}

		auto digitCount = getDigitCount(state);
		result <<= (4 * digitCount);
		result |= parseHexDigits(s, digitCount);
		s = s[digitCount .. $];

		if (s.length > 0 && s[0] == '_') {
			s = s[1 .. $];
			continue;
		}

		return result;
	}
}

unittest {
	assert(strToHexInt("") == 0);
	assert(strToHexInt("0") == 0);
	assert(strToHexInt("A") == 10);
	assert(strToHexInt("a") == 10);
	assert(strToHexInt("F") == 15);
	assert(strToHexInt("f") == 15);
	assert(strToHexInt("42") == 66);
	assert(strToHexInt("AbCdEf0") == 180150000);
	assert(strToHexInt("12345aBcDeF") == 1251004370415);
	assert(strToHexInt("12345aBcDeF0") == 20016069926640);
	assert(strToHexInt("FFFFFFFFFFFFFFFF") == 18446744073709551615);
	assert(strToHexInt("123456789abcdef") == 81985529216486895);
	assert(strToHexInt("a_B_c") == 2748);
	assert(strToHexInt("_01") == 1);
}
