module d.semantic.mangler;

import d.semantic.semantic;

import d.ir.symbol;
import d.ir.type;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct TypeMangler {
	private SemanticPass pass;
	alias pass this;

	this(SemanticPass pass) {
		this.pass = pass;
	}

	string visit(Type t) {
		auto s = t.accept(this);
		final switch (t.qualifier) with (TypeQualifier) {
			case Mutable:
				return s;

			case Inout:
				return "Ng" ~ s;

			case Const:
				return "x" ~ s;

			case Shared:
				return "O" ~ s;

			case ConstShared:
				return "xO" ~ s;

			case Immutable:
				return "y" ~ s;
		}
	}

	string visit(BuiltinType t) {
		final switch (t) with (BuiltinType) {
			case None:
				assert(0, "none should never be mangled");

			case Void:
				return "v";

			case Bool:
				return "b";

			case Char:
				return "a";

			case Wchar:
				return "u";

			case Dchar:
				return "w";

			case Byte:
				return "g";

			case Ubyte:
				return "h";

			case Short:
				return "s";

			case Ushort:
				return "t";

			case Int:
				return "i";

			case Uint:
				return "k";

			case Long:
				return "l";

			case Ulong:
				return "m";

			case Cent:
				// Used for ifloat, that won't be implemented.
				return "o";

			case Ucent:
				// Used for idouble, that won't be implemented.
				return "p";

			case Float:
				return "f";

			case Double:
				return "d";

			case Real:
				return "e";

			case Null:
				assert(0, "Mangling for typeof(null) is not Implemented");
		}
	}

	string visitPointerOf(Type t) {
		return "P" ~ visit(t);
	}

	string visitSliceOf(Type t) {
		return "A" ~ visit(t);
	}

	string visitArrayOf(uint size, Type t) {
		import std.conv;
		return "G" ~ size.to!string() ~ visit(t);
	}

	string visit(Struct s) {
		scheduler.require(s, Step.Populated);
		return s.mangle.toString(context);
	}

	string visit(Class c) {
		scheduler.require(c, Step.Populated);
		return c.mangle.toString(context);
	}

	string visit(Enum e) {
		scheduler.require(e);
		return e.mangle.toString(context);
	}

	string visit(TypeAlias a) {
		scheduler.require(a);
		return a.mangle.toString(context);
	}

	string visit(Interface i) {
		scheduler.require(i, Step.Populated);
		return i.mangle.toString(context);
	}

	string visit(Union u) {
		scheduler.require(u, Step.Populated);
		return u.mangle.toString(context);
	}

	string visit(Function f) {
		return "M";
	}

	string visit(Type[] splat) {
		assert(0, "Not implemented.");
	}

	private auto mangleParam(ParamType t) {
		return (t.isRef ? "K" : "") ~ visit(t.getType());
	}

	private auto mangleLinkage(Linkage linkage) {
		switch (linkage) with (Linkage) {
			case D:
				return "F";

			case C:
				return "U";
			/+
			case Windows :
				return "W";
			
			case Pascal :
				return "V";
			
			case CXX :
				return "R";
			+/
			default:
				import std.conv;
				assert(0,
				       "Linkage " ~ to!string(linkage) ~ " is not supported.");
		}
	}

	string visit(FunctionType f) {
		auto base = f.contexts.length ? "D" : "";
		auto linkage = mangleLinkage(f.linkage);

		import std.algorithm, std.range;
		auto args = f.parameters.map!(p => mangleParam(p)).join();
		auto ret = mangleParam(f.returnType);
		return base ~ linkage ~ args ~ "Z" ~ ret;
	}

	string visit(Pattern p) {
		assert(0, "Can't mangle pattern.");
	}

	import d.ir.error;
	string visit(CompileError e) {
		import source.exception;
		throw new CompileException(e.location, e.message);
	}
}

struct ConstantMangler {
	import d.ir.constant;
	string visit(Constant c) {
		return this.dispatch(c);
	}

	string visit(BooleanConstant b) {
		return b.value ? "0" : "1";
	}

	string visit(IntegerConstant i) {
		if (!isSigned(i.type.builtin)) {
			import std.conv;
			return to!string(i.value);
		}

		import std.conv;
		long v = i.value;
		return v >= 0 ? to!string(v) : "N" ~ to!string(-v);
	}

	string visit(StringConstant s) {
		auto ret = "a";
		auto str = s.value;
		auto len = str.length;

		ret.reserve(len * 2 + 8);

		import std.conv;
		ret ~= to!string(len);
		ret ~= '_';
		foreach (ubyte c; str) {
			ret ~= byte2hex(c);
		}

		return ret;
	}
}

private:

char[2] byte2hex(const ubyte b) pure {
	static immutable char[16] hexDigits = "0123456789abcdef";
	ubyte hi = (b >> 4);
	ubyte lo = (b & 0x0F);
	return [hexDigits[hi], hexDigits[lo]];
}

unittest {
	assert(byte2hex(0) == "00");
	assert(byte2hex(42) == "2a");
	assert(byte2hex(255) == "ff");
}

unittest {
	void check(string s, string m) {
		import d.ir.constant;
		auto c = new StringConstant(s);

		assert(ConstantMangler().visit(c) == m);
	}

	check("Hello World", "a11_48656c6c6f20576f726c64");
	check("©", "a2_c2a9");
}
