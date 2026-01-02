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
		return getZeroTerminatedContent()[0 .. $ - 1];
	}

	string getZeroTerminatedContent() {
		return sourceManager.getContent(this);
	}

	string getSlice(Location loc) {
		auto i = getOffset(loc.start);
		return getContent()[i .. i + loc.length];
	}

	FullPosition getWithOffset(uint offset) {
		auto p = sourceManager.getBase(this).getWithOffset(offset)
		                      .getFullPosition(context);

		assert(p.getSource() == this, "Position overflow!");
		return p;
	}

	FullPosition getLineOffset(uint line) {
		auto e = &sourceManager.getSourceEntry(this);
		auto p = e.base.getWithOffset(e.getLineOffset(line))
		          .getFullPosition(context);

		assert(p.getSource() == this, "Position overflow!");
		return p;
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
		return Location(sourceManager.getBase(this), p).length;
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
	Position registerFileZeroTerminated(
		Location location,
		Name filename,
		Name directory,
		string content
	) out(result; result.isFile()) {
		return files
			.registerFileZeroTerminated(location, filename, directory, content);
	}

	Position registerFile(Location location, Name filename, Name directory,
	                      string content) out(result; result.isFile()) {
		return files.registerFile(location, filename, directory, content);
	}

	Position registerMixinZeroTerminated(Location location, string content)
			out(result; result.isMixin()) {
		return mixins.registerMixinZeroTerminated(location, content);
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
		auto o = Location(e.base, p).length;
		return e.getLineNumber(o);
	}

	DebugLocation getDebugLocation(
		Position p,
		bool useLineDirective = EnableLineDirectiveByDefault
	) {
		// Find an actual file.
		while (p.isMixin()) {
			p = getImportLocation(getFileID(p)).start;
		}

		auto id = getFileID(p);
		auto e = &getSourceEntry(id);
		auto o = Location(e.base, p).length;

		auto filename = e.filename;
		auto line = e.getLineNumber(o);
		auto column = o - e.getLineOffset(line);

		if (useLineDirective && e.hasLineDirectives) {
			assert(0, "Line directive not supported!");
		}

		return DebugLocation(filename, line + 1, column + 1);
	}

	void registerLineDirective(Position p, Name filename, uint line) {
		auto id = getFileID(p);

		getSourceEntry(id).hasLineDirectives = true;
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

	Position getBase(FileID f) {
		return getSourceEntry(f).base;
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

	Position registerFileZeroTerminated(Location location, Name filename,
	                                    Name directory, string content) in {
		assert(nextSourcePos.isFile());
		assert(content.isZeroTerminated());
	} do {
		auto base = nextSourcePos;
		nextSourcePos = nextSourcePos.getWithOffset(cast(uint) content.length);
		sourceEntries ~=
			SourceEntry(base, location, filename, directory, content);
		return base;
	}

	Position registerFile(Location location, Name filename, Name directory,
	                      string content) in(nextSourcePos.isFile()) {
		content ~= '\0';
		return
			registerFileZeroTerminated(location, filename, directory, content);
	}

	Position registerMixinZeroTerminated(Location location, string content) in {
		assert(nextSourcePos.isMixin());
		assert(content.isZeroTerminated());
	} do {
		auto base = nextSourcePos;
		nextSourcePos = nextSourcePos.getWithOffset(cast(uint) content.length);
		sourceEntries ~= SourceEntry(base, location, content);
		return base;
	}

	Position registerMixin(Location location, string content)
			in(nextSourcePos.isMixin()) {
		content ~= '\0';
		return registerMixinZeroTerminated(location, content);
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
			lookup!(e => e.offset, 8)(sourceEntries, p.offset, lastFileID),
			p.isMixin()
		);
	}
}

struct SourceEntry {
private:
	Position _base;
	alias _base this;

	uint lastLineLookup;
	immutable(uint)[] lines;

	Location location;
	string _content;

	Name _filename;
	Name _directory;

	import std.bitmanip;
	mixin(bitfields!(
		// sdfmt off
		bool, "hasLineDirectives", 1,
		ulong, "_pad", ulong.sizeof * 8 - 1,
		// sdfmt on
	));

	// Make sure this is compact enough to fit in a cache line.
	static assert(SourceEntry.sizeof == 8 * size_t.sizeof);

public:
	@property
	Position base() const {
		return _base;
	}

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
		this._base = base;
		this.location = location;
		_content = content;
	}

	this(Position base, Location location, Name filename, Name directory,
	     string content) in(base.isFile()) {
		this._base = base;
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
			lastLineLookup = lookup!(l => l, 16)(lines, index, lastLineLookup);
		}

		return lastLineLookup;
	}

	uint getLineOffset(uint line) in(line <= lines.length) {
		return (line == lines.length) ? cast(uint) content.length : lines[line];
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

private bool isZeroTerminated(string content) {
	return content.length != 0 && content[$ - 1] == '\0';
}
