module d.semantic.typepromotion;

import d.semantic.semantic;

import d.ir.symbol;
import d.ir.type;

import source.location;

import source.exception;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

Type getPromotedType(SemanticPass pass, Location location, Type t1, Type t2) {
	return TypePromoter(pass, location, t1).visit(t2);
}

// XXX: type promotion and finding common type are mixed up in there.
// This need to be splitted.
struct TypePromoter {
	// XXX: Used only to get to super class, should probably go away.
	private SemanticPass pass;
	alias pass this;

	private Location location;

	Type t1;

	this(SemanticPass pass, Location location, Type t1) {
		this.pass = pass;
		this.location = location;

		this.t1 = t1.getCanonical();
	}

	Type visit(Type t) {
		return t.accept(this);
	}

	Type visit(BuiltinType bt) {
		auto t = t1.getCanonicalAndPeelEnum();

		if (bt == BuiltinType.Null) {
			if (t.kind == TypeKind.Pointer || t.kind == TypeKind.Class) {
				return t;
			}

			if (t.kind == TypeKind.Function
				    && t.asFunctionType().contexts.length == 0) {
				return t;
			}
		}

		if (t.kind == TypeKind.Builtin) {
			return Type.get(promoteBuiltin(bt, t.builtin));
		}

		import std.conv;
		return getError(
			t,
			location,
			"Can't coerce " ~ bt.to!string() ~ " to " ~ t.toString(context),
		).type;
	}

	Type visitPointerOf(Type t) {
		if (t1.kind == TypeKind.Builtin && t1.builtin == BuiltinType.Null) {
			return t.getPointer();
		}

		if (t1.kind != TypeKind.Pointer) {
			assert(0, "Not Implemented.");
		}

		auto e = t1.element;
		if (t.getCanonical().unqual() == e.getCanonical().unqual()) {
			if (canConvert(e.qualifier, t.qualifier)) {
				return t.getPointer();
			}

			if (canConvert(t.qualifier, e.qualifier)) {
				return e.getPointer();
			}
		}

		assert(0, "Not Implemented: use caster.");
	}

	Type visitSliceOf(Type t) {
		assert(0, "Not Implemented.");
	}

	Type visitArrayOf(uint size, Type t) {
		assert(0, "Not Implemented.");
	}

	Type visit(Struct s) {
		if (t1.kind == TypeKind.Struct && t1.dstruct is s) {
			return Type.get(s);
		}

		import source.exception;
		throw new CompileException(
			location,
			"Incompatible struct type " ~ s.name.toString(context) ~ " and "
				~ t1.toString(context)
		);
	}

	Type visit(Class c) {
		if (t1.kind == TypeKind.Builtin && t1.builtin == BuiltinType.Null) {
			return Type.get(c);
		}

		if (t1.kind != TypeKind.Class) {
			assert(0, "Not Implemented.");
		}

		auto r = t1.dclass;

		// Find a common superclass.
		scheduler.require(c, Step.Signed);
		auto cp = c.primaries;

		scheduler.require(r, Step.Signed);
		auto rp = r.primaries;

		import std.algorithm;
		auto i = min(cp.length, rp.length);
		while (i-- > 0) {
			if (cp[i] is rp[i]) {
				return Type.get(cp[i]);
			}
		}

		// We did not find a common ancestor, fallback on object.
		return Type.get(pass.object.getObject());
	}

	Type visit(Enum e) {
		return visit(e.type);
	}

	Type visit(TypeAlias a) {
		return visit(a.type);
	}

	Type visit(Interface i) {
		assert(0, "Not Implemented.");
	}

	Type visit(Union u) {
		assert(0, "Not Implemented.");
	}

	Type visit(Function f) {
		assert(0, "Not Implemented.");
	}

	Type visit(Type[] seq) {
		assert(0, "Not Implemented.");
	}

	Type visit(FunctionType f) {
		assert(0, "Not Implemented.");
	}

	Type visit(Pattern p) {
		assert(0, "Not implemented.");
	}

	import d.ir.error;
	Type visit(CompileError e) {
		return e.type;
	}
}

private:

BuiltinType getBuiltinBase(BuiltinType t) {
	if (t == BuiltinType.Bool) {
		return BuiltinType.Int;
	}

	if (isChar(t)) {
		return integralOfChar(t);
	}

	return t;
}

BuiltinType promoteBuiltin(BuiltinType t1, BuiltinType t2) {
	t1 = getBuiltinBase(t1);
	t2 = getBuiltinBase(t2);

	if (isIntegral(t1) && isIntegral(t2)) {
		import std.algorithm;
		return max(t1, t2, BuiltinType.Int);
	}

	assert(0, "Not implemented.");
}

unittest {
	with (BuiltinType) {
		foreach (t1; [Bool, Char, Wchar, Byte, Ubyte, Short, Ushort, Int]) {
			foreach (t2; [Bool, Char, Wchar, Byte, Ubyte, Short, Ushort, Int]) {
				assert(promoteBuiltin(t1, t2) == Int);
			}
		}

		foreach (t1;
			[Bool, Char, Wchar, Dchar, Byte, Ubyte, Short, Ushort, Int, Uint]
		) {
			foreach (t2; [Dchar, Uint]) {
				assert(promoteBuiltin(t1, t2) == Uint);
				assert(promoteBuiltin(t2, t1) == Uint);
			}
		}

		foreach (t; [Bool, Char, Wchar, Dchar, Byte, Ubyte, Short, Ushort, Int,
		             Uint, Long]) {
			assert(promoteBuiltin(t, Long) == Long);
			assert(promoteBuiltin(Long, t) == Long);
		}

		foreach (t; [Bool, Char, Wchar, Dchar, Byte, Ubyte, Short, Ushort, Int,
		             Uint, Long, Ulong]) {
			assert(promoteBuiltin(t, Ulong) == Ulong);
			assert(promoteBuiltin(Ulong, t) == Ulong);
		}

		foreach (t; [Bool, Char, Wchar, Dchar, Byte, Ubyte, Short, Ushort, Int,
		             Uint, Long, Ulong, Cent]) {
			assert(promoteBuiltin(t, Cent) == Cent);
			assert(promoteBuiltin(Cent, t) == Cent);
		}

		foreach (t; [Bool, Char, Wchar, Dchar, Byte, Ubyte, Short, Ushort, Int,
		             Uint, Long, Ulong, Cent, Ucent]) {
			assert(promoteBuiltin(t, Ucent) == Ucent);
			assert(promoteBuiltin(Ucent, t) == Ucent);
		}
	}
}
