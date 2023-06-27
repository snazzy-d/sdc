module source.util.identifier;

import source.util.charset;
import source.util.unicode_tables;

immutable ulong[32] XID_Start_Dual = generateDualByteLookupTable(XID_Start);
immutable
ubyte[4096] XID_Start_Roots = generateTrieRoots(XID_Start, XID_Start_Leaves);
immutable ulong[246] XID_Start_Leaves = generateTrieLeaves(XID_Start);

uint identifierStartLength(string s) {
	auto c = s[0];
	if (c < 0x80) {
		import source.util.ascii;
		return isAsciiIdStart(c);
	}

	char next = s[1];
	if (isDualByteCodePoint(c, next)) {
		return matchDualByteCodepoint(XID_Start_Dual, c, next) ? 2 : 0;
	}

	dchar d;
	uint index = 0;

	import source.util.utf8;
	if (!decode(s, index, d)) {
		return 0;
	}

	if (!matchTrieCodepoint(XID_Start_Roots, XID_Start_Leaves, d)) {
		return 0;
	}

	return index;
}

bool expectsIdentifier(string s) {
	return identifierStartLength(s) > 0;
}

unittest {
	static check(dchar d, bool doesStart) {
		char[4] buf;

		import std.utf;
		auto i = encode(buf, d);
		auto expected = doesStart ? i : 0;

		auto s = cast(string) buf[];
		assert(expectsIdentifier(s) == doesStart);
		assert(identifierStartLength(s) == expected);
	}

	foreach (r; XID_Start) {
		check(r[0] - 1, false);
		check(r[1], false);

		foreach (dchar d; r[0] .. r[1]) {
			check(d, true);
		}
	}

	// Unicode does not consider `_` an XID_Start,
	// so we need to make sure we special case ASCII.
	check('_', true);

	foreach (char c; 0 .. 0x80) {
		import source.util.ascii;
		check(c, isAsciiIdStart(c));
	}
}

uint skipIdentifier(string s) {
	auto index = identifierStartLength(s);
	if (index == 0) {
		return 0;
	}

	return skipIdContinue(s, index);
}

unittest {
	static check(dchar d, bool doesStart) {
		char[4] buf;

		import std.utf;
		auto i = encode(buf, d);
		auto expected = doesStart ? i : 0;

		auto s = cast(string) buf[0 .. i];
		assert(skipIdentifier(s ~ '\0') == expected);
		assert(skipIdentifier(s ~ ' ') == expected);

		expected = doesStart ? i + 3 : 0;
		assert(skipIdentifier(s ~ "aaa\0") == expected);

		expected = doesStart ? i + 4 : 0;
		assert(skipIdentifier(s ~ "·ɑ\0") == expected);
	}

	foreach (r; XID_Start) {
		check(r[0] - 1, false);
		check(r[1], false);

		foreach (dchar d; r[0] .. r[1]) {
			check(d, true);
		}
	}
}

immutable
ulong[32] XID_Continue_Dual = generateDualByteLookupTable(XID_Continue);
immutable ubyte[4096] XID_Continue_Roots =
	generateTrieRoots(XID_Continue, XID_Continue_Leaves);
immutable ulong[256] XID_Continue_Leaves = generateTrieLeaves(XID_Continue);

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

		char next = s[index + 1];
		if (isDualByteCodePoint(c, next)) {
			if (!matchDualByteCodepoint(XID_Continue_Dual, c, next)) {
				return index;
			}

			index += 2;
			continue;
		}

		dchar d;
		uint i = index;

		import source.util.utf8;
		if (!decode(s, i, d)) {
			return index;
		}

		// The [0xe0100 .. 0xe01ef] range needs to be special cased or
		// the trie gets 4x larger just to accomodate it!
		bool isIdeographicSpecificVariationSelector =
			0xe0100 <= d && d <= 0xe01ef;

		// We avoid short circuiting here, because the special cased range
		// is incredibly uncommon.
		bool matchTrie =
			matchTrieCodepoint(XID_Continue_Roots, XID_Continue_Leaves, d);

		if (matchTrie || isIdeographicSpecificVariationSelector) {
			index = i;
			continue;
		}

		return index;
	}
}

unittest {
	static check(dchar d, bool doesContinue) {
		char[4] buf;

		import std.utf;
		auto i = encode(buf, d);
		auto expected = doesContinue ? i : 0;

		auto s = cast(string) buf[0 .. i];
		assert(skipIdContinue(s ~ '\0', 0) == expected);
		assert(skipIdContinue(s ~ ' ', 0) == expected);

		expected = doesContinue ? i + 3 : 0;
		assert(skipIdContinue(s ~ "aaa\0", 0) == expected);
	}

	foreach (r; XID_Continue) {
		check(r[0] - 1, false);
		check(r[1], false);

		foreach (dchar d; r[0] .. r[1]) {
			check(d, true);
		}
	}
}
