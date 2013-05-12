module d.location;

import std.utf;
import std.range;
import std.string;
import std.system;

/**
 * Struct representing a location in a source file.
 */
struct Location {
	Source source;
	
	uint line = 1;
	uint index = 1;
	uint length = 0;
	
	string toString() const {
		return source.format(this);
	}
	
	void spanTo(ref const Location end) in {
		assert(source is end.source, "locations must have the same source !");
		
		assert(line <= end.line);
		assert(index <= end.index);
		assert(index + length <= end.index + end.length);
	} body {
		length = end.index - index + end.length;
	}
}

abstract class Source {
	string content;
	
	this(string content) {
		this.content = content;
	}
	
	abstract string format(const Location location) const;
	
	@property
	abstract string filename() const;
}

final class FileSource : Source {
	string _filename;
	
	this(string filename) {
		_filename = filename;
		
		import std.file;
		auto data = cast(const(ubyte)[]) read(filename);
		super(convertToUTF8(data) ~ '\0');
	}
	
	override string format(const Location location) const {
		import std.conv;
		return _filename ~ ':' ~ to!string(location.line);
	}
	
	@property
	override string filename() const {
		return _filename;
	}
}

final class MixinSource : Source {
	Location location;
	
	this(Location location, string content) {
		this.location = location;
		super(content);
	}
	
	override string format(const Location dummy) const {
		return location.toString();
	}
	
	@property
	override string filename() const {
		return location.source.filename;
	}
}

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

