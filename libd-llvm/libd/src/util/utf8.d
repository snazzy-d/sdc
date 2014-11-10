module util.utf8;

import std.utf; // toUTF8
import std.string; // startsWith
import std.range; // iota
import std.system; // Endian

/// Given data, it looks at the BOM to detect which encoding, and converts
/// the text from that encoding into UTF-8.
string convertToUTF8(const(ubyte)[] data) {
	if (data.startsWith([0xEF, 0xBB, 0xBF])) {
		// UTF-8 (toUTF8 is for validation purposes)
		return toUTF8(cast(string) data[3 .. $].idup);
	} else if (data.startsWith([0x00, 0x00, 0xFE, 0xFF])) {
		// UTF-32 BE
		return convertToUTF8Impl!(dchar, Endian.bigEndian)(data);
	} else if (data.startsWith([0xFF, 0xFE, 0x00, 0x00])) {
		// UTF-32 LE
		return convertToUTF8Impl!(dchar, Endian.littleEndian)(data);
	} else if (data.startsWith([0xFE, 0xFF])) {
		// UTF-16 BE
		return convertToUTF8Impl!(wchar, Endian.bigEndian)(data);
	} else if (data.startsWith([0xFF, 0xFE])) {
		// UTF-16 LE
		return convertToUTF8Impl!(wchar, Endian.littleEndian)(data);
	} else {
		// ASCII
		return toUTF8(cast(string)data.idup);
	}
}

string convertToUTF8Impl(CType, Endian end)(const(ubyte)[] data) {
	enum cpsize = CType.sizeof;
	data = data[cpsize .. $];
	CType[] res;
	foreach(i; iota(0, data.length, cpsize)) {
		auto buf = data[i .. i+cpsize].dup;
		static if (end != endian) {
			buf = buf.reverse;
		}
		res ~= *(cast(CType*)buf.ptr);
	}
	return toUTF8(res);
}

