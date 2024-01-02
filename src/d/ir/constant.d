module d.ir.constant;

import source.context;
import source.location;
import source.name;

import d.ir.type;

abstract class Constant {
	Type type;

	this(Type type) {
		this.type = type;
	}

	string toString(const Context) const {
		import std.format;
		assert(0, format!"toString not implement for %s."(typeid(this)));
	}
}

final:

/**
 * Used for type identifier = void;
 */
class VoidConstant : Constant {
	this(Type type) {
		super(type);
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"void(%s)"(type.toString(c));
	}
}

/**
 * Null literal.
 */
class NullConstant : Constant {
	this() {
		this(Type.get(BuiltinType.Null));
	}

	this(Type t) {
		super(t);
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"null(%s)"(type.toString(c));
	}
}
