module d.context.sourcemanager;

import d.context.location;
import d.context.source;

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
		
		assert(
			sourceManager.getFileID(start) == sourceManager.getFileID(stop),
			"Location file mismatch"
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
	Position registerFile(string filename) out(result) {
		assert(result.isFile());
	} body {
		auto s = new FileSource(filename);
		return files.registerSource(s);
	}
	
	Position registerMixin(Location location, string content) out(result) {
		assert(result.isMixin());
	} body {
		auto s = new MixinSource(location, content);
		return mixins.registerSource(s);
	}
	
package:
	static get() {
		return SourceManager();
	}
	
private:
	Source getSource(Position p) {
		return getSourceEntry(p).source;
	}
	
	string getContent(Position p) {
		return getSource(p).content;
	}
	
	string getFileName(Position p) in {
		assert(p.isFile());
	} body {
		return getSourceEntry(p).fileSource.filename;
	}
	
	FullLocation getImportLocation(Position p) in {
		assert(p.isMixin());
	} body {
		return getSourceEntry(p).mixinSource.location.getFullLocation(this);
	}
	
	uint getLineNumber(Position p) {
		auto e = &getSourceEntry(p);
		return e.source.getLineNumber(p.offset - e.base.offset);
	}
	
	uint getColumn(Position p) {
		auto e = &getSourceEntry(p);
		auto o = p.offset - e.base.offset;
		return o - e.source.getLineOffset(o);
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
	
	Position registerSource(S)(S s) if(is(S : Source)) {
		auto base = nextSourcePos;
		nextSourcePos = nextSourcePos
			.getWithOffset(cast(uint) s.content.length);
		sourceEntries ~= SourceEntry(base, s);
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
	Position base;
	alias base this;
	
private:
	union {
		Source _source;
		FileSource _fileSource;
		MixinSource _mixinSource;
	}
	
private:
	this(Position base, FileSource source) in {
		assert(base.isFile());
	} body {
		this.base = base;
		_fileSource = source;
	}
	
	this(Position base, MixinSource source) in {
		assert(base.isMixin());
	} body {
		this.base = base;
		_mixinSource = source;
	}
	
	@property
	inout(FileSource) fileSource() inout in {
		assert(base.isFile());
	} body {
		return _fileSource;
	}
	
	@property
	inout(MixinSource) mixinSource() inout in {
		assert(base.isMixin());
	} body {
		return _mixinSource;
	}
	
	@property
	inout(Source) source() inout {
		return _source;
	}
}
