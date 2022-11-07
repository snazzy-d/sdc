module source.util.utf8;

import std.system;

/**
 * This function decode a codepoint from an utf-8 string.
 * 
 * It uses a state machine as decribed by Björn Höhrmann in
 * http://bjoern.hoehrmann.de/utf-8/decoder/dfa/
 * Archive: https://archive.ph/LVY0U
 */
bool decode(string s, ref size_t index, ref dchar decoded) {
	static immutable ubyte[256] TypeTable = [
		// sdfmt off
		 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 00 .. 0f
		 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 10 .. 1f
		 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 20 .. 2f
		 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 30 .. 3f
		 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 40 .. 4f
		 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 50 .. 5f
		 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 60 .. 6f
		 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 70 .. 7f
		 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, // 80 .. 8f
		 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, // 90 .. 9f
		 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // a0 .. af
		 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // b0 .. bf
		 8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // c0 .. cf
		 2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // d0 .. df
		10,3,3,3,3,3,3,3,3,3,3,3,3,4,3,3, // e0 .. ef
		11,6,6,6,5,8,8,8,8,8,8,8,8,8,8,8, // f0 .. ff
		// sdfmt on
	];

	static immutable ubyte[108] StateTable = [
		// sdfmt off
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

	enum Types = TypeTable.ptr;
	enum States = StateTable.ptr;

	char c = s[index];
	uint type = Types[c];
	uint state = States[type];
	uint codepoint = c & (0xff >> type);

	for (index = index + 1; (state > 12) && (index < s.length); index++) {
		c = s[index];
		codepoint = (c & 0x3f) | (codepoint << 6);
		type = Types[c];
		state = States[state + type];
	}

	decoded = cast(dchar) codepoint;
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

	// Check we don't go past the end of the string.
	foreach (s; ["\xE2\x89", "\xC0\x8A", "\xE0\x80\x8A", "\xF0\x80\x80\x8A",
	             "\xF8\x80\x80\x80\x8A", "\xFC\x80\x80\x80\x80\x8A"]) {
		size_t index = 0;
		assert(!decode(s, index, decoded));

		index = 1;
		assert(!decode(s, index, decoded));
		assert(index == 2);
	}

	// Invalid UTF-8 sequences.
	foreach (s; ["\xED\xA0\x80", "\xED\xAD\xBF", "\xED\xAE\x80", "\xED\xAF\xBF",
	             "\xED\xB0\x80", "\xED\xBE\x80", "\xED\xBF\xBF"]) {
		size_t index = 0;
		assert(!decode(s, index, decoded));
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
