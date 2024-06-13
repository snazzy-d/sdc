module d.ir.constant;

import source.context;

import d.ir.type;
import d.ir.value;

abstract class Constant : Value {
	this(Type type) {
		super(type);
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

class BooleanConstant : Constant {
	bool value;

	this(bool value) {
		super(Type.get(BuiltinType.Bool));

		this.value = value;
	}

	override string toString(const Context) const {
		return value ? "true" : "false";
	}
}

class IntegerConstant : Constant {
	ulong value;

	this(ulong value, BuiltinType type) in(isIntegral(type)) {
		super(Type.get(type));

		this.value = value;
	}

	override string toString(const Context) const {
		import std.conv;
		return isSigned(type.builtin)
			? to!string(cast(long) value)
			: to!string(value);
	}
}

class FloatConstant : Constant {
	double value;

	this(double value, BuiltinType t) in(isFloat(t)) {
		super(Type.get(t));

		this.value = value;
	}

	override string toString(const Context) const {
		import std.conv;
		return to!string(value);
	}
}

class CharacterConstant : Constant {
	uint value;

	this(uint value, BuiltinType type) in(isChar(type)) {
		super(Type.get(type));

		this.value = value;
	}

	this(char value) {
		this(value, BuiltinType.Char);
	}

	this(dchar value) {
		this(value, BuiltinType.Dchar);
	}

	override string toString(const Context) const {
		dchar[1] x = [dchar(value)];

		import std.format;
		return format!"%(%s%)"(x);
	}
}

class StringConstant : Constant {
	string value;

	this(string value) {
		super(Type.get(BuiltinType.Char).getSlice(TypeQualifier.Immutable));

		this.value = value;
	}

	override string toString(const Context) const {
		string[1] x = [value];

		import std.format;
		return format!"%(%s%)"(x);
	}
}

class CStringConstant : Constant {
	string value;

	this(string value) {
		super(Type.get(BuiltinType.Char).getPointer(TypeQualifier.Immutable));

		this.value = value;
	}

	override string toString(const Context) const {
		string[1] x = [value];

		import std.format;
		return format!"%(%s%)"(x);
	}
}

class ArrayConstant : Constant {
	Constant[] elements;

	this(Type type, Constant[] elements) {
		super(type.getArray(cast(uint) elements.length));

		this.elements = elements;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"[%-(%s, %)]"(elements.map!(e => e.toString(c)));
	}
}

class AggregateConstant : Constant {
	Constant[] elements;

	import d.ir.symbol;
	this(S)(S s, Constant[] elements) if (is(S : Aggregate)) {
		super(Type.get(s));

		this.elements = elements;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"%s(%-(%s, %))"(type.aggregate.name.toString(c),
		                              elements.map!(e => e.toString(c)));
	}
}

class UnionConstant : Constant {
	Constant value;

	import d.ir.symbol;
	this(Union u, Constant value) {
		super(Type.get(u));

		this.value = value;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"%s(%s)"(type.dunion.name.toString(c), value.toString(c));
	}
}

class SplatConstant : Constant {
	Constant[] elements;

	this(Type type, Constant[] elements) {
		super(type);

		this.elements = elements;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"(%-(%s, %))"(elements.map!(e => e.toString(c)));
	}
}

class FunctionConstant : Constant {
	import d.ir.symbol;
	Function fun;

	this(Function fun) {
		super(fun.type.getType());

		this.fun = fun;
	}

	override string toString(const Context c) const {
		return fun.name.toString(c);
	}
}

/**
 * typeid(type) expression.
 * 
 * TODO: Consider hanlding this as a regular symbol instead of
 *       special casing typeid.
 */
class TypeidConstant : Constant {
	Type argument;

	this(Type type, Type argument) {
		super(type);

		this.argument = argument;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"typeid(%s)"(argument.toString(c));
	}
}
