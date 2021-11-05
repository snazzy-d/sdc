module source.strtoint;

ulong strToInt(string s) in {
	assert(s.length > 0, "s must not be empty");
} do {
	if (s[0] != '0' || s.length < 3) {
		goto ParseDec;
	}
	
	switch(s[1]) {
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
	assert(strToInt("0") == 0);
	assert(strToInt("42") == 42);
	assert(strToInt("123") == 123);
	assert(strToInt("0x0") == 0);
	assert(strToInt("0xaa") == 170);
	assert(strToInt("0b101") == 5);
}

ulong strToDecInt(string s) in {
	assert(s.length > 0, "s must not be empty");
} do {
	ulong ret = 0;
	
	for (uint i = 0; i < s.length; i++) {
		if (s[i] == '_') continue;
		
		ret *= 10;
		
		auto d = s[i] - '0';
		assert(d < 10, "Only digits are expected here");
		ret += d;
	}
	
	return ret;
}

unittest {
	assert(strToDecInt("0") == 0);
	assert(strToDecInt("42") == 42);
	assert(strToDecInt("1234567890") == 1234567890);
	assert(strToDecInt("18446744073709551615") == 18446744073709551615UL);
	assert(strToDecInt("34_56") == 3456);
}

ulong strToBinInt(string s) in {
	assert(s.length > 0, "s must not be empty");
} do {
	ulong ret = 0;
	
	for (uint i = 0; i < s.length; i++) {
		if (s[i] == '_') continue;
		
		ret <<= 1;
		auto d = s[i] - '0';
		assert(d < 2, "Only 0 and 1 are expected here");
		ret |= d;
	}
	
	return ret;
}

unittest {
	assert(strToBinInt("0") == 0);
	assert(strToBinInt("1010") == 10);
	assert(strToBinInt("0101010") == 42);
	assert(strToBinInt(
		"1111111111111111111111111111111111111111111111111111111111111111",
	) == 18446744073709551615UL);
	assert(strToBinInt("11_101_00") == 116);
}

ulong strToHexInt(string s) in {
	assert(s.length > 0, "s must not be empty");
} do {
	ulong ret = 0;
	
	for (uint i = 0; i < s.length; i++) {
		// TODO: Filter these out at lexing.
		if (s[i] == '_') continue;
		
		// XXX: This would allow to reduce data dependacy here by using
		// the string length and shifting the whole amount at once.
		ret *= 16;
		
		auto d = s[i] - '0';
		if (d < 10) {
			ret += d;
			continue;
		}
		
		auto h = (s[i] | 0x20) - 'a' + 10;
		assert(h - 10 < 6, "Only hex digits are expected here");
		ret += h;
	}
	
	return ret;
}

unittest {
	assert(strToHexInt("0") == 0);
	assert(strToHexInt("A") == 10);
	assert(strToHexInt("a") == 10);
	assert(strToHexInt("F") == 15);
	assert(strToHexInt("f") == 15);
	assert(strToHexInt("42") == 66);
	assert(strToHexInt("AbCdEf0") == 180150000);
	assert(strToHexInt("12345aBcDeF") == 1251004370415);
	assert(strToHexInt("FFFFFFFFFFFFFFFF") == 18446744073709551615UL);
	assert(strToHexInt("a_B_c") == 2748);
}
