module source.util.ascii;

bool isAsciiIdStart(char c) {
	auto hc = c | 0x20;
	return c == '_' || (hc >= 'a' && hc <= 'z');
}

unittest {
	foreach (char c; 0 .. 0x80) {
		import std.ascii;
		bool expected = c == '_' || isAlpha(c);
		assert(isAsciiIdStart(c) == expected);
	}
}

bool isAsciiIdContinue(char c) {
	if (c & 0x80) {
		return false;
	}

	static test(char c) {
		return (c >= '0' && c <= '9') || isAsciiIdStart(c);
	}

	enum uint[4] Table = generateAsciiLookupTable!test();
	return lookupCharacter(Table, c);
}

unittest {
	foreach (char c; 0 .. 0x80) {
		import std.ascii;
		bool expected = c == '_' || isAlphaNum(c);
		assert(isAsciiIdContinue(c) == expected);
	}
}

bool isDecDigit(char c) {
	return c >= '0' && c <= '9';
}

bool isHexDigit(char c) {
	auto hc = c | 0x20;
	return (c >= '0' && c <= '9') || (hc >= 'a' && hc <= 'f');
}

uint[4] generateAsciiLookupTable(alias fun)() {
	uint[4] ret;

	foreach (char c; 0 .. 0x80) {
		uint t = fun(c) != 0;

		auto index = c >> 5;
		auto shift = c & 0x1f;
		ret[index] |= t << shift;
	}

	return ret;
}

bool lookupCharacter(uint[4] table, char c) in(c < 0x80) {
	auto index = c >> 5;
	auto mask = 1 << (c & 0x1f);
	return (table[index] & mask) != 0;
}
