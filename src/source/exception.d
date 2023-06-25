/**
 * This file is part of libd.
 * See LICENCE for more details.
 */
module source.exception;

class CompileException : Exception {
	import source.location;
	Location location;

	CompileException more; // Optional
	string fixHint; // Optional

	this(Location loc, string message) {
		super(message);
		location = loc;
	}

	this(Location loc, string message, CompileException more) {
		this.more = more;
		this(loc, message);
	}

	import source.context;
	auto getFullLocation(Context c) const {
		return location.getFullLocation(c);
	}
}

class IncompleteInputException : CompileException {
	import source.location;

	this(Location loc, string message) {
		super(loc, message);
	}

	this(Location loc, string message, CompileException more) {
		super(loc, message, more);
	}
}
