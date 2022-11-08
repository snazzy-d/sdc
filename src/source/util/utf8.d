module source.util.utf8;

import std.system;

/**
 * This function decode a codepoint from an utf-8 string.
 * 
 * It uses a state machine as decribed by Björn Höhrmann in
 * http://bjoern.hoehrmann.de/utf-8/decoder/dfa/
 * Archive: https://archive.ph/LVY0U
 * 
 * Some notes on the types:
 *  - [c0 .. c1] maps character on the ASCII range on two bytes.
 *    It is therefore banned using type 8, which always triggers
 *    and invalid sequence.
 *  - Similarly, [f5 .. ff] maps to invalid sequences and also
 *    has type 8.
 *  - e0 (type 10) only allows continuations in the
 *    [a0 .. bf] range (type 7).
 *    Continuations in the [80 .. 9f] range (type 1 and 9)
 *    would lead to codepoints which can be encoded using
 *    2 bytes and are therefore banned.
 *  - ed (type 4) only allows continuations in the
 *    [80 .. 9f] range (Type 1 and 9).
 *    Continuation in the [a0 .. bf] range (type 7) would
 *    lead to codepoint in the [d800 .. dfff] range, which
 *    is reserved for surrogate pairs for utf-16.
 *  - f0 (type 11) only allows continuations in the
 *    [90 .. af] range (Type 7 and 9).
 *    Continuations in the [80 .. 8f] range (type 1)
 *    would lead to codepoints which can be encoded using
 *    3 bytes and are therefore banned.
 *  - f4 (type 5) only allows continuations in the
 *    [80 .. 8f] range (Type 1).
 *    Continuations in the [90 .. bf] range (type 7 and 9)
 *    would lead to codepoints past 0x10FFFF, the highest
 *    possible codepoint.
 * 
 * In addition, the exact value of the type is chosen in
 * such a way that it can be used to mask prefix bits in
 * leading encoding character.
 */
private immutable ubyte[256 + 108] DecoderTable = [
	// sdfmt off
	// The first part of the table maps bytes to character classes.
	 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 00 .. 0f ^
	 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 10 .. 1f |
	 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 20 .. 2f |
	 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 30 .. 3f | 0xxxxxxx Block.
	 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 40 .. 4f |
	 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 50 .. 5f |
	 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 60 .. 6f |
	 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 70 .. 7f V
	 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, // 80 .. 8f ^
	 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, // 90 .. 9f | 10xxxxxx Block.
	 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // a0 .. af |
	 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // b0 .. bf V
	 8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // c0 .. cf ^ 110xxxxx Block.
	 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // d0 .. df V
	10,3,3,3,3,3,3,3,3,3,3,3,3,4,3,3, // e0 .. ef < 1110xxxx Block.
	11,6,6,6,5,8,8,8,8,8,8,8,8,8,8,8, // f0 .. ff < 1111xxxx Block.

	// The second part is a transition table that maps a combination
	// of a state of the automaton and a character class to a state.
	 0,12,24,36,60,96,84,12,12,12,48,72, // state = 0  : Done.
	12,12,12,12,12,12,12,12,12,12,12,12, // state = 12 : Failure.
	12, 0,12,12,12,12,12, 0,12, 0,12,12, // state = 24 : 1 more byte.
	12,24,12,12,12,12,12,24,12,24,12,12, // state = 36 : 2 more bytes.
	12,12,12,12,12,12,12,24,12,12,12,12, // state = 48 : e0
	12,24,12,12,12,12,12,12,12,24,12,12, // state = 60 : ed
	12,12,12,12,12,12,12,36,12,36,12,12, // state = 72 : f0
	12,36,12,12,12,12,12,36,12,36,12,12, // state = 84 : f1 .. f3
	12,36,12,12,12,12,12,12,12,12,12,12, // state = 96 : f4
	// sdfmt on
];

private enum Types = DecoderTable.ptr;
private enum States = DecoderTable.ptr + 256;

bool decode(string s, ref size_t index, ref dchar decoded) {
	char c = s[index];
	if (c < 0xc2 || c > 0xf4) {
		decoded = c;
		index++;
		return c < 0x80;
	}

	uint type = Types[c];
	uint state = States[type];
	assert(state > 12);

	uint codepoint = c & (0xff >> type);
	while ((state > 12) && (++index < s.length)) {
		c = s[index];
		codepoint = (c & 0x3f) | (codepoint << 6);
		type = Types[c];
		state = States[state + type];
	}

	decoded = cast(dchar) codepoint;
	index += state == 0;
	return state == 0;
}

bool decode(string s, ref uint index, ref dchar decoded) {
	size_t i = index;
	scope(exit) index = cast(uint) i;

	return decode(s, i, decoded);
}

unittest {
	dchar decoded;

	foreach (ubyte i; 0 .. 128) {
		size_t index = 0;
		assert(decode([i], index, decoded));
		assert(index == 1);
		assert(decoded == i);
	}

	foreach (ubyte i; 128 .. 256) {
		size_t index = 0;
		assert(!decode([i], index, decoded));
		assert(index == 1);
	}

	// Decode some valid strings.
	foreach (s; ["abcd", "ウェブサイト", "🂽Γαῖα🨁🙈🙉🙊🜚", "\xEF\xBF\xBE", "言語",
	             "𐁄𐂌𐃯 Ljósmóðir ディラン"]) {
		size_t index = 0;
		foreach (size_t i, dchar d; s) {
			assert(index == i);
			assert(decode(s, index, decoded));
			assert(decoded == d);
		}

		assert(index == s.length);
	}

	// Check we reject invalid sequences
	foreach (s; ["\xff\x88\xff", "\x80\xbf\xab", "\xbf\x80\xab", "\xc0\xc1\xc0",
	             "\xef\xcf\x7f", "\xc2\xd1\xe0"]) {
		size_t index = 0;
		assert(!decode(s, index, decoded));
		assert(index == 1);

		index = 1;
		assert(!decode(s, index, decoded));
		assert(index == 2);
	}

	// Check we don't go past the end of the string.
	foreach (s; ["\xc2", "\xe2\x89", "\xf1\x89\xab"]) {
		size_t index = 0;
		assert(!decode(s, index, decoded));
		assert(index == s.length);
	}

	// Do not eat into the next sequence when
	// dealing with invalid sequences.
	foreach (s; ["\xe4\0", "\xe4x", "\xe4😞"]) {
		size_t index = 0;
		assert(!decode(s, index, decoded));
		assert(index == 1);
	}

	// Check ranges of accepted codepoints.
	foreach (s; [
		// 1 byte encoding.
		"\x00",
		"\x42", "\x7f",
		// 2 bytes encoding.
		"\xc2\x80",
		"\xd0\xb0",
		"\xdf\xbf",
		// 3 bytes encoding, before surrogate pairs
		"\xe0\xa0\x80",
		"\xe2\xaa\xbb",
		"\xed\x9f\xbf",
		// 3 bytes encoding, after surrogate pairs
		"\xee\x80\x80",
		"\xee\x99\x88",
		"\xef\xbf\xbf",
		// 4 bytes encoding.
		"\xf0\x90\x80\x80",
		"\xf2\x8f\x9f\xaf",
		"\xf4\x8f\xbf\xbf",
	]) {
		size_t index = 0;
		assert(decode(s, index, decoded));
		assert(index == s.length);
	}

	// Reject valid looking, but actually invalid sequences.
	foreach (s; [
		// Redundant with 1 byte encoding.
		"\xc0\x80",
		"\xc0\xbb", "\xc1\xbf",
		// Redundant with 2 bytes encoding.
		"\xe0\x80\x80",
		"\xe0\x9a\x8b",
		"\xe0\x9f\xbf",
		// Redundant with surrogates pairs.
		"\xed\xa0\x80",
		"\xed\xaf\xba",
		"\xed\xbf\xbf",
		// Redundant with 3 bytes encoding.
		"\xf0\x80\x80\x80",
		"\xf0\x88\x99\x88",
		"\xf0\x8f\xbf\xbf",
		// Encode characters past U+10ffff
		"\xf4\x90\x80\x80",
		"\xf4\xbf\xbf\xbf",
		"\xf5\x80\x80\x80",
		"\xf7\xbf\xbf\xbf",
		// 5 bytes encoding is disallowed.
		"\xf8\xaa\x80\x80\x80",
		// 6 bytes encoding is disallowed.
		"\xfc\xaa\x80\x80\x80\x80",
		// 7 bytes encoding is disallowed.
		"\xfe\xaa\x80\x80\x80\x80\x80",
		// 8 bytes encoding (?) is disallowed.
		"\xff\xaa\x80\x80\x80\x80\x80\x80",
	]) {
		size_t index = 0;
		assert(!decode(s, index, decoded));
		assert(index == 1);
	}
}

/**
 * Given data, it looks at the BOM to detect which encoding, and converts
 * the text from that encoding into UTF-8.
 */
string convertToUTF8(const(ubyte)[] data) {
	import std.string;
	if (data.startsWith([0xEF, 0xBB, 0xBF])) {
		// UTF-8 (toUTF8 is for validation purposes)
		import std.utf;
		return toUTF8(cast(string) data[3 .. $].idup);
	}

	if (data.startsWith([0x00, 0x00, 0xFE, 0xFF])) {
		// UTF-32 BE
		return convertToUTF8Impl!(dchar, Endian.bigEndian)(data);
	}

	if (data.startsWith([0xFF, 0xFE, 0x00, 0x00])) {
		// UTF-32 LE
		return convertToUTF8Impl!(dchar, Endian.littleEndian)(data);
	}

	if (data.startsWith([0xFE, 0xFF])) {
		// UTF-16 BE
		return convertToUTF8Impl!(wchar, Endian.bigEndian)(data);
	}

	if (data.startsWith([0xFF, 0xFE])) {
		// UTF-16 LE
		return convertToUTF8Impl!(wchar, Endian.littleEndian)(data);
	}

	// ASCII or raw UTF-8, just pass through.
	return cast(string) data.idup;
}

string convertToUTF8Impl(C, Endian E)(const(ubyte)[] data) {
	enum S = C.sizeof;
	data = data[S .. $];

	C[] res;

	import std.range;
	foreach (i; iota(0, data.length, S)) {
		ubyte[S] buf = data[i .. i + S];
		static if (E != endian) {
			import std.algorithm : reverse;
			reverse(buf[]);
		}

		res ~= *(cast(C*) buf.ptr);
	}

	import std.utf;
	return toUTF8(res);
}
