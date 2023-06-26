module source.util.identifier;

uint identifierStartLength(string s) {
	auto c = s[0];
	if (c < 0x80) {
		import source.util.ascii;
		return isAsciiIdStart(c);
	}

	dchar d;
	uint index = 0;

	import source.util.utf8;
	if (!decode(s, index, d)) {
		return 0;
	}

	import std.uni;
	return isAlpha(d) ? index : 0;
}

bool expectsIdentifier(string s) {
	return identifierStartLength(s) > 0;
}

uint skipIdentifier(string s) {
	auto index = identifierStartLength(s);
	if (index == 0) {
		return 0;
	}

	return skipIdContinue(s, index);
}

uint skipIdContinue(string s, uint index) {
	while (true) {
		char c = s[index];
		while (c < 0x80) {
			import source.util.ascii;
			if (!isAsciiIdContinue(c)) {
				return index;
			}

			c = s[++index];
		}

		dchar d;
		uint i = index;

		import source.util.utf8;
		if (!decode(s, i, d)) {
			return index;
		}

		import std.uni;
		if (!isAlphaNum(d)) {
			return index;
		}

		index = i;
	}
}
