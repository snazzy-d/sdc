module d.context.source;

import d.context.location;

abstract class Source {
private:
	string _content;
	immutable(uint)[] lines;
	uint lastLineLookup;
	
public:
	this(string content) {
		_content = content;
	}
	
final:
	@property
	string content() const {
		return _content;
	}

package:
	uint getLineNumber(uint index) {
		if (!lines) {
			lines = getLines(content);
		}

		// It is common to query the same file many time,
		// so we have a one entry cache for it.
		if (!isIndexInLine(index, lastLineLookup)) {
			import util.lookup;
			lastLineLookup = lookup!(l => l, 15)(
				lines,
				index,
				lastLineLookup,
			);
		}

		return lastLineLookup + 1;
	}

private:
	bool isIndexInLine(uint index, uint line) {
		if (index < lines[line]) {
			return false;
		}

		return (line + 1 == lines.length)
			? (index < content.length)
			: (index < lines[line + 1]);
	}
}

final class FileSource : Source {
private:
	string _filename;
	
public:
	this(string filename) {
		this._filename = filename;
		
		import std.file;
		auto data = cast(const(ubyte)[]) read(filename);

		import util.utf8;
		super(convertToUTF8(data) ~ '\0');
	}
	
	@property
	auto filename() const {
		return _filename;
	}
}

final class MixinSource : Source {
	Location location;
	
	this(Location location, string content) {
		this.location = location;
		super(content);
	}
}

// XXX: This need to be vectorized
immutable(uint)[] getLines(string content) {
	immutable(uint)[] ret = [];

	uint p = 0;
	uint i = 0;
	char c = content[i];
	while (true) {
		while(c != '\n' && c != '\r' && c != '\0') {
			c = content[++i];
		}

		if (c == '\0') {
			ret ~= p;
			return ret;
		}

		auto match = c;
		c = content[++i];

		// \r\n is a special case
		if (match == '\r' && c == '\n') {
			c = content[++i];
		}

		ret ~= p;
		p = i;
	}
}
