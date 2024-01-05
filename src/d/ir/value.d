module d.ir.value;

import source.context;

import d.ir.type;

abstract class Value {
	Type type;

	this(Type type) {
		this.type = type;
	}

	string toString(const Context) const {
		import std.format;
		assert(0, format!"toString not implement for %s."(typeid(this)));
	}
}
