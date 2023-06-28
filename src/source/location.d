module source.location;

import source.context;

/**
 * Struct representing a location in a source file.
 * Effectively a pair of Position within the source file.
 */
struct Location {
package:
	Position _start;
	Position _stop;

public:
	this(Position start, Position stop) in {
		assert(start.isMixin() == stop.isMixin());
		assert(start.offset <= stop.offset);
	} do {
		this._start = start;
		this._stop = stop;
	}

	@property
	Position start() const {
		return _start;
	}

	@property
	Position stop() const {
		return _stop;
	}

	@property
	uint length() const {
		return stop.offset - start.offset;
	}

	@property
	bool isFile() const {
		return start.isFile();
	}

	@property
	bool isMixin() const {
		return start.isMixin();
	}

	auto spanTo(Location end) in {
		import std.conv;
		assert(stop.offset <= end.stop.offset,
		       to!string(stop.offset) ~ " > " ~ to!string(end.stop.offset));
	} do {
		return spanTo(end.stop);
	}

	auto spanTo(Position end) const in {
		import std.conv;
		assert(stop.offset <= end.offset,
		       to!string(stop.offset) ~ " > " ~ to!string(end.offset));
	} do {
		return Location(start, end);
	}

	auto getFullLocation(Context c) const {
		return FullLocation(this, c);
	}
}

/**
 * Struct representing a position in a source file.
 */
struct Position {
private:
	import std.bitmanip;
	mixin(bitfields!(
		// sdfmt off
		uint, "_offset", uint.sizeof * 8 - 1,
		bool, "_mixin", 1,
		// sdfmt on
	));

package:
	@property
	uint offset() const {
		return _offset;
	}

	@property
	uint raw() const {
		return *(cast(uint*) &this);
	}

public:
	bool isFile() const {
		return !_mixin;
	}

	bool isMixin() const {
		return _mixin;
	}

	Position getWithOffset(uint offset) const
			out(result; result.isMixin() == isMixin(), "Position overflow") {
		return Position(raw + offset);
	}

	Location getWithOffsets(uint start, uint stop) {
		return Location(getWithOffset(start), getWithOffset(stop));
	}

	auto getFullPosition(Context c) const {
		return FullPosition(this, c);
	}

	int opCmp(Position rhs) const {
		return raw - rhs.raw;
	}
}

/**
 * A Location associated with a context, so it can probe various infos.
 */
struct FullLocation {
private:
	Location _location;
	Context context;

	@property
	inout(FullPosition) start() inout {
		return inout(FullPosition)(location.start, context);
	}

	@property
	inout(FullPosition) stop() inout {
		return inout(FullPosition)(location.stop, context);
	}

	@property
	ref sourceManager() inout {
		return context.sourceManager;
	}

public:
	this(Location location, Context context) {
		this._location = location;
		this.context = context;

		import std.conv;
		assert(
			length == 0 || start.getSource()
				== Position(stop.raw - 1).getFullPosition(context).getSource(),
			/+
			"Location file mismatch " ~
				start.getFileName() ~ ":" ~ to!string(getStartOffset()) ~ " and " ~
				stop.getFileName() ~ ":" ~ to!string(getStopOffset())
			/* +/ /*/ /+ */
			"Location file mismatch"
		// +/
		);
	}

	alias location this;
	@property
	auto location() const {
		return _location;
	}

	auto getSource() out(result; result.isMixin() == isMixin()) {
		return start.getSource();
	}

	auto getFileName() {
		return getSource().getFileName();
	}

	string getSlice() {
		return getSource().getSlice(this);
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
		return start.getSourceOffset();
	}

	uint getStopOffset() {
		return stop.getSourceOffset();
	}
}

/**
 * A Position associated with a context, so it can probe various infos.
 */
struct FullPosition {
private:
	Position _position;
	Context context;

	@property
	uint offset() const {
		return position.offset;
	}

	@property
	ref sourceManager() inout {
		return context.sourceManager;
	}

public:
	alias position this;
	@property
	auto position() const {
		return _position;
	}

	auto getSource() out(result; result.isMixin() == isMixin()) {
		return sourceManager.getFileID(this).getSource(context);
	}

	uint getLineNumber() {
		return sourceManager.getLineNumber(this);
	}

	uint getColumn() {
		return sourceManager.getColumn(this);
	}

	uint getSourceOffset() {
		return getSource().getOffset(this);
	}
}
