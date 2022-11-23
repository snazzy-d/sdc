module source.manager;

import source.context;
import source.location;
import source.name;

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
	@property
	auto file() const {
		return _file;
	}

	string getContent() {
		return sourceManager.getContent(this);
	}

	string getSlice(Location loc) {
		return getContent()[getOffset(loc.start) .. getOffset(loc.stop)];
	}

	FullName getFileName() {
		return sourceManager.getFileName(this).getFullName(context);
	}

	FullName getDirectory() in(isFile()) {
		return sourceManager.getDirectory(this).getFullName(context);
	}

	FullLocation getImportLocation() {
		return sourceManager.getImportLocation(this).getFullLocation(context);
	}

package:
	uint getOffset(Position p)
			in(p.getFullPosition(context).getSource() == this) {
		return p.offset - sourceManager.getOffset(this);
	}
}

struct LineDirectives {
	struct LineEntry {
		Position position;
		Name filename;
		uint line;
	}

	LineEntry[] lineDirectives;

	this(Position p, Name filename, uint line) {
		lineDirectives = [LineEntry(p, filename, line)];
	}

	void registerLineDirective(Position p, Name filename, uint line) {
		if (lineDirectives[$ - 1].position < p) {
			lineDirectives ~= LineEntry(p, filename, line);
		}
	}
}

struct SourceManager {
private:
	SourceEntries files = SourceEntries(1);
	SourceEntries mixins = SourceEntries(int.min);

	LineDirectives[FileID] lineDirectives;

	// Make it non copyable.
	@disable
	this(this);

public:
	Position registerFile(Location location, Name filename, Name directory,
	                      string content) out(result; result.isFile()) {
		return files.registerFile(location, filename, directory, content);
	}

	Position registerMixin(Location location, string content)
			out(result; result.isMixin()) {
		return mixins.registerMixin(location, content);
	}

	FileID getFileID(Position p) out(result; p.isMixin() == result.isMixin()) {
		return p.isFile() ? files.getFileID(p) : mixins.getFileID(p);
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

	void registerLineDirective(Position p, Name filename, uint line) {
		auto id = getFileID(p);

		getSourceEntry(id)._hasLineDirectives = true;
		lineDirectives.update(
			id,
			() => LineDirectives(p, filename, line),
			(ref LineDirectives ds) =>
				ds.registerLineDirective(p, filename, line)
		);
	}

package:
	static get() {
		return SourceManager();
	}

private:
	string getContent(FileID f) {
		return getSourceEntry(f).content;
	}

	uint getOffset(FileID f) {
		return getSourceEntry(f).base.offset;
	}

	Name getFileName(FileID f) {
		return getSourceEntry(f).filename;
	}

	Name getDirectory(FileID f) in(f.isFile()) {
		return getSourceEntry(f).directory;
	}

	Location getImportLocation(FileID f) {
		return getSourceEntry(f).location;
	}

	ref SourceEntry getSourceEntry(Position p) {
		return getSourceEntry(getFileID(p));
	}

	ref SourceEntry getSourceEntry(FileID f) {
		return f.isFile() ? files.sourceEntries[f] : mixins.sourceEntries[f];
	}
}

struct FileID {
private:
	import std.bitmanip;
	mixin(bitfields!(
		// sdfmt off
		bool, "_mixin", 1,
		uint, "_index", uint.sizeof * 8 - 1,
		// sdfmt on
	));

	this(uint id, bool isMixin) {
		this._index = id;
		this._mixin = isMixin;
	}

public:
	alias id this;
	@property
	auto id() const {
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

	Position registerFile(Location location, Name filename, Name directory,
	                      string content) in(nextSourcePos.isFile()) {
		auto base = nextSourcePos;
		nextSourcePos = nextSourcePos.getWithOffset(cast(uint) content.length);
		sourceEntries ~=
			SourceEntry(base, location, filename, directory, content);
		return base;
	}

	Position registerMixin(Location location, string content)
			in(nextSourcePos.isMixin()) {
		auto base = nextSourcePos;
		nextSourcePos = nextSourcePos.getWithOffset(cast(uint) content.length);
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
	} do {
		// It is common to query the same file many time,
		// so we have a one entry cache for it.
		if (isPositionInFileID(p, lastFileID)) {
			return lastFileID;
		}

		import source.util.lookup;
		return lastFileID = FileID(
			lookup!(e => e.offset, 7)(sourceEntries, p.offset, lastFileID),
			p.isMixin()
		);
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

	import std.bitmanip;
	mixin(bitfields!(
		// sdfmt off
		bool, "_hasLineDirectives", 1,
		ulong, "_pad", ulong.sizeof * 8 - 1,
		// sdfmt on
	));

	// Make sure this is compact enough to fit in a cache line.
	static assert(SourceEntry.sizeof == 8 * size_t.sizeof);

public:
	@property
	string content() const {
		return _content;
	}

	@property
	auto filename() const in(base.isFile()) {
		return _filename;
	}

	@property
	auto directory() const in(base.isFile()) {
		return _directory;
	}

private:
	this(Position base, Location location, string content) in(base.isMixin()) {
		this.base = base;
		this.location = location;
		_content = content;
	}

	this(Position base, Location location, Name filename, Name directory,
	     string content) in(base.isFile()) {
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
			import source.util.lookup;
			lastLineLookup = lookup!(l => l, 15)(lines, index, lastLineLookup);
		}

		return lastLineLookup + 1;
	}

	uint getLineOffset(uint index) out(result; result <= index) {
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

immutable(uint)[] getLines(string content) in(content.length < uint.max) {
	static struct LineBreakLexer {
		string content;
		uint index;

		this(string content) {
			this.content = content;
		}

		import source.lexbase;
		mixin LexBaseUtils;

		import source.lexwhitespace;
		mixin LexWhiteSpaceImpl;

		auto computeLineSplits() {
			immutable(uint)[] ret = [0];

			while (!reachedEOF()) {
				popLine();
				ret ~= index;
			}

			return ret;
		}
	}

	return LineBreakLexer(content).computeLineSplits();
}
