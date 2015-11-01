module d.context.source;

import d.context.context;
import d.context.location;
import d.context.name;

struct Source {
private:
	FileID _file;
	Context context;
	
	@property
	ref sourceManager() inout {
		return context.sourceManager;
	}
	
public:
	alias file this;
	@property file() const {
		return _file;
	}
	
	string getContent() {
		return sourceManager.getContent(this);
	}
	
	FullName getFileName() {
		return sourceManager.getFileName(this).getFullName(context);
	}
	
	FullName getDirectory() {
		return sourceManager.getDirectory(this).getFullName(context);
	}
	
	FullLocation getImportLocation() {
		return sourceManager
			.getImportLocation(this)
			.getFullLocation(context);
	}
}

struct SourceManager {
private:
	SourceEntries files = SourceEntries(1);
	SourceEntries mixins = SourceEntries(int.min);
	
	// Make it non copyable.
	@disable this(this);
	
public:
	Position registerFile(
		Location location,
		Name filename,
		Name directory,
		string content,
	) out(result) {
		assert(result.isFile());
	} body {
		return files.registerFile(location, filename, directory, content);
	}
	
	Position registerMixin(Location location, string content) out(result) {
		assert(result.isMixin());
	} body {
		return mixins.registerMixin(location, content);
	}
	
	FileID getFileID(Position p) out(result) {
		assert(p.isMixin() == result.isMixin());
	} body {
		return p.isFile()
			? files.getFileID(p)
			: mixins.getFileID(p);
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
	
package:
	static get() {
		return SourceManager();
	}
	
private:
	string getContent(FileID f) {
		return getSourceEntry(f).content;
	}
	
	Name getFileName(FileID f) {
		return getSourceEntry(f).filename;
	}
	
	Name getDirectory(FileID f) in {
		assert(f.isFile());
	} body {
		return getSourceEntry(f).directory;
	}
	
	Location getImportLocation(FileID f) {
		return getSourceEntry(f).location;
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

struct FileID {
private:
	import std.bitmanip;
	mixin(bitfields!(
		bool, "_mixin", 1,
		uint, "_index", uint.sizeof * 8 - 1,
	));
	
	this(uint id, bool isMixin) {
		this._index = id;
		this._mixin = isMixin;
	}
	
public:
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
	
	Source getSource(Context c) {
		return Source(this, c);
	}
}

unittest {
	uint i = 1;
	auto f = *cast(FileID*) &i;
	
	assert(f.isMixin());
	assert(f.id == 0);
}

private:

struct SourceEntries {
	SourceEntry[] sourceEntries;
	Position nextSourcePos;
	FileID lastFileID;
	
	this(uint base) {
		nextSourcePos = Position(base);
		lastFileID = FileID(0, nextSourcePos.isMixin());
	}
	
	Position registerFile(
		Location location,
		Name filename,
		Name directory,
		string content,
	) in {
		assert(nextSourcePos.isFile());
	} body {
		auto base = nextSourcePos;
		nextSourcePos = nextSourcePos
			.getWithOffset(cast(uint) content.length);
		sourceEntries ~=
			SourceEntry(base, location, filename, directory, content);
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
	
	Name _filename;
	Name _directory;
	
	ulong pad;
	
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
	
	@property
	auto directory() const in {
		assert(base.isFile());
	} body {
		return _directory;
	}
	
private:
	this(Position base, Location location, string content) in {
		assert(base.isMixin());
	} body {
		this.base = base;
		this.location = location;
		_content = content;
	}
	
	this(
		Position base,
		Location location,
		Name filename,
		Name directory,
		string content,
	) in {
		assert(base.isFile());
	} body {
		this.base = base;
		this.location = location;
		_content = content;
		_filename = filename;
		_directory = directory;
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
