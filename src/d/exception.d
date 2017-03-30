/**
 * This file is part of libd.
 * See LICENCE for more details.
 */
module d.exception;

class CompileException : Exception {
	import d.context.location;
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

	import d.context.context;
	auto getFullLocation(Context c) const {
		return location.getFullLocation(c);
	}
}
