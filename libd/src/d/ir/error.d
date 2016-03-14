module d.ir.error;

import d.context.context;
import d.context.location;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

class CompileError {
	Location location;
	string message;
	
	void[StorageSize!ErrorSymbol] symStorage;
	void[StorageSize!ErrorExpression] exprStorage;
	
public:
	this(Location location, string message) {
		this.location = location;
		this.message = message;
		
		import std.conv;
		symStorage.emplace!ErrorSymbol(this);
		exprStorage.emplace!ErrorExpression(this);
	}
	
	string toString(const Context) const {
		return message;
	}
	
final:
	@property
	auto symbol() inout {
		return cast(inout(ErrorSymbol)) symStorage.ptr;
	}
	
	@property
	auto expression() inout {
		return cast(inout(ErrorExpression)) exprStorage.ptr;
	}
	
	@property
	auto type() {
		import d.ir.type;
		return Type.get(this);
	}
}

CompileError getError(T)(T t, Location location, string msg) {
	import d.ir.type;
	static if (is(T : Expression)) {
		if (auto e = cast(ErrorExpression) t) {
			return e.error;
		}
	} else static if (is(T : Symbol)) {
		if (auto e = cast(ErrorSymbol) t) {
			return e.error;
		}
	} else static if (is(T : Type)) {
		if (t.kind == TypeKind.Error) {
			return t.error;
		}
	} else {
		static assert(0, "Unepxected " ~ typeid(t).toString());
	}
	
	return new CompileError(location, msg);
}

CompileError errorize(E)(E e) if (is(E : Expression)) {
	static if (is(ErrorExpression : E)) {
		if (auto ee = cast(ErrorExpression) e) {
			return ee.error;
		}
	}
	
	return null;
}

CompileError errorize(S)(S s) if (is(S : Symbol)) {
	static if (is(ErrorSymbol : S)) {
		if (auto es = cast(ErrorSymbol) s) {
			return es.error;
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
	foreach(t; ts) {
		if (auto ce = errorize(t)) {
			return ce;
		}
	}
	
	return null;
}

CompileError errorize(T...)(T ts) if (T.length > 1) {
	foreach(t; ts) {
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
 * An Error occured but an Expression is expected.
 * Useful for speculative compilation.
 */
class ErrorExpression : CompileTimeExpression {
// private:
	this(CompileError error) {
		import d.ir.type;
		super(error.location, Type.get(error));
	}
	
	invariant() {
		import d.ir.type;
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
 * An Error occured but a Symbol is expected.
 * Useful for speculative compilation.
 */
class ErrorSymbol : Symbol {
	CompileError error;
	
// private:
	this(CompileError error) {
		import d.context.name;
		super(error.location, BuiltinName!"");
		
		this.error = error;
		step = Step.Processed;
	}
	
public:
	override string toString(const Context c) const {
		return "__error__(" ~ error.toString(c) ~ ")";
	}
}

private:
template StorageSize(T) {
	enum InstanceSize = __traits(classInstanceSize, T);
	enum PtrSize = ((InstanceSize - 1) / size_t.sizeof) + 1;
	enum StorageSize = PtrSize * size_t.sizeof;
}
