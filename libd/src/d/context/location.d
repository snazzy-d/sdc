module d.context.location;

import d.context.context;

/**
 * Struct representing a location in a source file.
 * Effectively a pair of Position within the source file.
 */
struct Location {
package:
	Position start;
	Position stop;
	
public:
	this(Position start, Position stop) in {
		assert(start.isMixin() == stop.isMixin());
		assert(start.offset <= stop.offset);
	} body {
		this.start = start;
		this.stop = stop;
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
	
	void spanTo(ref const Location end) in {
		import std.conv;
		assert(
			stop.offset <= end.stop.offset,
			to!string(stop.offset) ~ " > " ~ to!string(end.stop.offset)
		);
	} body {
		spanTo(end.stop);
	}
	
	void spanTo(ref const Position end) in {
		import std.conv;
		assert(
			stop.offset <= end.offset,
			to!string(stop.offset) ~ " > " ~ to!string(end.offset)
		);
	} body {
		stop = end;
	}
	
	auto getFullLocation(Context c) const {
		import d.context.sourcemanager;
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
		uint, "_offset", uint.sizeof * 8 - 1,
		bool, "_mixin", 1,
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
	
	bool isFile() const {
		return !_mixin;
	}
	
	bool isMixin() const {
		return _mixin;
	}
	
public:
	Position getWithOffset(uint offset) const out(result) {
		assert(result.isMixin() == isMixin(), "Position overflow");
	} body {
		return Position(raw + offset);
	}
	
	auto getFullPosition(Context c) const {
		import d.context.sourcemanager;
		return FullPosition(this, c);
	}
}
