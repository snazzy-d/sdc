module d.context.sourcemanager;

import d.context.location;

struct FullLocation {
private:
	Location _location;
	SourceManager* sourceManager;
	
	@property
	inout(FullPosition) start() inout {
		return inout(FullPosition)(location.start, sourceManager);
	}
	
	@property
	inout(FullPosition) stop() inout {
		return inout(FullPosition)(location.stop, sourceManager);
	}
	
public:
	this(Location location, SourceManager* sourceManager) {
		this._location = location;
		this.sourceManager = sourceManager;
		
		import std.conv;
		assert(
			sourceManager.getFileID(start) == sourceManager.getFileID(stop),
/+
			"Location file mismatch " ~
				start.getFileName() ~ ":" ~ to!string(start.getOffsetInFile()) ~ " and " ~
				stop.getFileName() ~ ":" ~ to!string(stop.getOffsetInFile())
/* +/ /*/ /+ */
			"Location file mismatch"
// +/
		);
	}
	
	@property
	Location location() const {
		return _location;
	}
	
	alias location this;
	
	string getContent() {
		return start.getContent();
	}
	
	string getFileName() {
		return start.getFileName();
	}
	
	string getDirectory() {
		return start.getDirectory();
	}
	
	FullLocation getImportLocation() {
		return start.getImportLocation();
	}
	
	uint getStartLineNumber() {
		return start.getLineNumber();
	}
	
	uint getStopLineNumber() {
		return stop.getLineNumber();
	}
	
	uint getStartColumn() {
		return start.getColumn();
	}
	
	uint getStopColumn() {
		return stop.getColumn();
	}
	
	uint getStartOffset() {
		return start.getOffsetInFile();
	}
	
	uint getStopOffset() {
		return stop.getOffsetInFile();
	}
}

struct FullPosition {
private:
	Position _position;
	SourceManager* sourceManager;
	
	@property
	uint offset() const {
		return position.offset;
	}
	
public:
	@property
	Position position() const {
		return _position;
	}
	
	alias position this;
	
	string getContent() {
		return sourceManager.getContent(this);
	}
	
	string getFileName() {
		return sourceManager.getFileName(this);
	}
	
	string getDirectory() {
		return sourceManager.getDirectory(this);
	}
	
	FullLocation getImportLocation() {
		return sourceManager.getImportLocation(this);
	}
	
	uint getLineNumber() {
		return sourceManager.getLineNumber(this);
	}
	
	uint getColumn() {
		return sourceManager.getColumn(this);
	}
	
	uint getOffsetInFile() {
		return sourceManager.getOffsetInFile(this);
	}
}

struct SourceManager {
private:
	SourceEntries files = SourceEntries(1);
	SourceEntries mixins = SourceEntries(int.min);
	
	// Make it non copyable.
	@disable this(this);
	
public:
	Position registerFile(Location location, string filename) out(result) {
		assert(result.isFile());
	} body {
		return files.registerFile(location, filename);
	}
	
	Position registerMixin(Location location, string content) out(result) {
		assert(result.isMixin());
	} body {
		return mixins.registerMixin(location, content);
	}
	
package:
	static get() {
		return SourceManager();
	}
	
private:
	string getContent(Position p) {
		return getSourceEntry(p).content;
	}
	
	string getFileName(Position p) in {
		assert(p.isFile());
	} body {
		return getSourceEntry(p).filename;
	}
	
	string getDirectory(Position p) in {
		assert(p.isFile());
	} body {
		return "";
	}
	
	FullLocation getImportLocation(Position p) in {
		assert(p.isMixin());
	} body {
		return getSourceEntry(p).location.getFullLocation(this);
	}
	
	uint getLineNumber(Position p) {
		auto e = &getSourceEntry(p);
		return e.getLineNumber(p.offset - e.base.offset);
	}
	
	uint getColumn(Position p) {
		auto e = &getSourceEntry(p);
		auto o = p.offset - e.base.offset;
		return o - e.getLineOffset(o);
	}
	
	uint getOffsetInFile(Position p) {
		return p.offset - getSourceEntry(p).offset;
	}
	
	FileID getFileID(Position p) out(result) {
		assert(p.isMixin() == result.isMixin());
	} body {
		return p.isFile()
			? files.getFileID(p)
			: mixins.getFileID(p);
	}
	
	ref SourceEntry getSourceEntry(Position p) {
		return getSourceEntry(getFileID(p));
	}
	
	ref SourceEntry getSourceEntry(FileID f) {
		return f.isFile()
			? files.sourceEntries[f]
			: mixins.sourceEntries[f];
	}
}

private:

struct FileID {
	import std.bitmanip;
	mixin(bitfields!(
		bool, "_mixin", 1,
		uint, "_index", uint.sizeof * 8 - 1,
	));
	
	this(uint id, bool isMixin) {
		this._index = id;
		this._mixin = isMixin;
	}
	
	alias id this;
	@property id() const {
		return _index;
	}
	
	bool isFile() const {
		return !_mixin;
	}
	
	bool isMixin() const {
		return _mixin;
	}
}

struct SourceEntries {
	SourceEntry[] sourceEntries;
	Position nextSourcePos;
	FileID lastFileID;
	
	this(uint base) {
		nextSourcePos = Position(base);
		lastFileID = FileID(0, nextSourcePos.isMixin());
	}
	
	Position registerFile(Location location, string filename) in {
		assert(nextSourcePos.isFile());
	} body {
		import std.file;
		auto data = cast(const(ubyte)[]) read(filename);
		
		import util.utf8;
		auto content = convertToUTF8(data) ~ '\0';
		
		auto base = nextSourcePos;
		nextSourcePos = nextSourcePos
			.getWithOffset(cast(uint) content.length);
		sourceEntries ~= SourceEntry(base, location, filename, content);
		return base;
	}
	
	Position registerMixin(Location location, string content) in {
		assert(nextSourcePos.isMixin());
	} body {
		auto base = nextSourcePos;
		nextSourcePos = nextSourcePos
			.getWithOffset(cast(uint) content.length);
		sourceEntries ~= SourceEntry(base, location, content);
		return base;
	}
	
	bool isPositionInFileID(Position p, FileID fileID) {
		auto offset = p.offset;
		if (offset < sourceEntries[fileID].offset) {
			return false;
		}
		
		return (fileID + 1 == sourceEntries.length)
			? (offset < nextSourcePos.offset)
			: (offset < sourceEntries[fileID + 1].offset);
	}
	
	FileID getFileID(Position p) in {
		assert(p.isMixin() == nextSourcePos.isMixin());
		assert(p.offset < nextSourcePos.offset);
	} body {
		// It is common to query the same file many time,
		// so we have a one entry cache for it.
		if (!isPositionInFileID(p, lastFileID)) {
			import util.lookup;
			lastFileID = FileID(lookup!(e => e.offset, 7)(
				sourceEntries,
				p.offset,
				lastFileID,
			), p.isMixin());
		}
		
		return lastFileID;
	}
}

struct SourceEntry {
private:
	Position base;
	alias base this;
	
	uint lastLineLookup;
	immutable(uint)[] lines;
	
	Location location;
	string _content;
	
	string _filename;
	
	// Make sure this is compact enough to fit in a cache line.
	static assert(SourceEntry.sizeof == 8 * size_t.sizeof);
	
public:
	@property
	string content() const {
		return _content;
	}
	
	@property
	auto filename() const in {
		assert(base.isFile());
	} body {
		return _filename;
	}
	
private:
	this(Position base, Location location, string content) in {
		assert(base.isMixin());
	} body {
		this.base = base;
		this.location = location;
		_content = content;
	}
	
	this(Position base, Location location, string filename, string content) in {
		assert(base.isFile());
	} body {
		this.base = base;
		this.location = location;
		_content = content;
		_filename = filename;
	}
	
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
	
	uint getLineOffset(uint index) out(result) {
		assert(result <= index);
	} body {
		return lines[getLineNumber(index) - 1];
	}
	
	bool isIndexInLine(uint index, uint line) {
		if (index < lines[line]) {
			return false;
		}
		
		return (line + 1 == lines.length)
			? (index < content.length)
			: (index < lines[line + 1]);
	}
}

// XXX: This need to be vectorized
immutable(uint)[] getLines(string content) {
	immutable(uint)[] ret = [];
	
	uint p = 0;
	uint i = 0;
	char c = content[i];
	while (true) {
		while (c != '\n' && c != '\r' && c != '\0') {
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
