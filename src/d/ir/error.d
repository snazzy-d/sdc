module d.ir.error;

import source.context;
import source.location;

import d.ir.constant;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

class CompileError {
	Location location;
	string message;

	void[StorageSize!ErrorSymbol] symbolStorage;
	void[StorageSize!ErrorExpression] exprStorage;
	void[StorageSize!ErrorExpression] constantStorage;

public:
	this(Location location, string message) {
		this.location = location;
		this.message = message;

		import std.conv;
		symbolStorage.emplace!ErrorSymbol(this);
		exprStorage.emplace!ErrorExpression(this);
		constantStorage.emplace!ErrorConstant(this);
	}

	string toString(const Context) const {
		return message;
	}

final:
	@property
	auto symbol() inout {
		return cast(inout(ErrorSymbol)) symbolStorage.ptr;
	}

	@property
	auto expression() inout {
		return cast(inout(ErrorExpression)) exprStorage.ptr;
	}

	@property
	auto constant() inout {
		return cast(inout(ErrorConstant)) constantStorage.ptr;
	}

	@property
	auto type() {
		return Type.get(this);
	}
}

CompileError getError(T)(T t, Location location, string msg)
		if (isErrorizable!T) {
	if (auto e = errorize(t)) {
		return e;
	}

	return new CompileError(location, msg);
}

CompileError errorize(S)(S s) if (is(S : Symbol)) {
	static if (is(ErrorSymbol : S)) {
		if (auto es = cast(ErrorSymbol) s) {
			return es.error;
		}
	}

	return null;
}

CompileError errorize(E)(E e) if (is(E : Expression)) {
	static if (is(ErrorExpression : E)) {
		if (auto ee = cast(ErrorExpression) e) {
			return ee.error;
		}
	}

	static if (is(ConstantExpression : E)) {
		if (auto ce = cast(ConstantExpression) e) {
			return errorize(ce.value);
		}
	}

	return null;
}

CompileError errorize(C)(C c) if (is(C : Constant)) {
	static if (is(ErrorConstant : C)) {
		if (auto ec = cast(ErrorConstant) c) {
			return ec.error;
		}
	}

	return null;
}

CompileError errorize(Type t) {
	if (t.kind == TypeKind.Error) {
		return t.error;
	}

	return null;
}

enum isErrorizable(T) = is(typeof(errorize(T.init)));

CompileError errorize(T)(T[] ts) if (isErrorizable!T) {
	foreach (t; ts) {
		if (auto ce = errorize(t)) {
			return ce;
		}
	}

	return null;
}

CompileError errorize(T...)(T ts) if (T.length > 1) {
	foreach (t; ts) {
		// XXX: https://issues.dlang.org/show_bug.cgi?id=15360
		static if (isErrorizable!(typeof(t))) {
			if (auto ce = errorize(t)) {
				return ce;
			}
		}
	}

	return null;
}

final:
/**
 * An Error occured but a Symbol is expected.
 * Useful for speculative compilation.
 */
class ErrorSymbol : Symbol {
	CompileError error;

	// private:
	this(CompileError error) {
		import source.name;
		super(error.location, BuiltinName!"");

		this.error = error;
		step = Step.Processed;
	}

public:
	override string toString(const Context c) const {
		import std.format;
		return format!"__error__(%s)"(error.toString(c));
	}
}

/**
 * An Error occured but an Expression is expected.
 * Useful for speculative compilation.
 */
class ErrorExpression : CompileTimeExpression {
	// private:
	this(CompileError error) {
		super(error.location, Type.get(error));
	}

	invariant() {
		assert(type.kind == TypeKind.Error);
	}

public:
	@property
	auto error() {
		return type.error;
	}

	override string toString(const Context c) const {
		return type.toString(c);
	}
}

/**
 * An Error occured but a Constant is expected.
 * Useful for speculative compilation.
 */
class ErrorConstant : Constant {
	// private:
	this(CompileError error) {
		super(Type.get(error));
	}

	invariant() {
		assert(type.kind == TypeKind.Error);
	}

public:
	@property
	auto error() {
		return type.error;
	}

	override string toString(const Context c) const {
		return type.toString(c);
	}
}

private:
template StorageSize(T) {
	enum InstanceSize = __traits(classInstanceSize, T);
	enum PtrSize = ((InstanceSize - 1) / size_t.sizeof) + 1;
	enum StorageSize = PtrSize * size_t.sizeof;
}
