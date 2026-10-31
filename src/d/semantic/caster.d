module d.semantic.caster;

import d.semantic.semantic;
import d.semantic.typepromotion;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;
import d.ir.value;

import source.location;

import source.exception;

Expression buildImplicitCast(SemanticPass pass, Location location, Type to,
                             Expression e) {
	return buildCast!false(pass, location, to, e);
}

Expression buildExplicitCast(SemanticPass pass, Location location, Type to,
                             Expression e) {
	return buildCast!true(pass, location, to, e);
}

Value buildImplicitCast(SemanticPass pass, Location location, Type to,
                        Value value) {
	return buildCast!false(pass, location, to, value);
}

Value buildExplicitCast(SemanticPass pass, Location location, Type to,
                        Value value) {
	return buildCast!true(pass, location, to, value);
}

Value buildImplicitCast(SemanticPass pass, Location location, ParamType to,
                        Value value) {
	return buildCast!false(pass, location, to, value);
}

CastKind implicitCastFrom(SemanticPass pass, Type from, Type to) {
	return ImplicitCaster(pass, to).castFrom(from);
}

/**
 * The implicit cast of a value of type from to a value of type to. A
 * reference can only bind to something that has an address, as a pointer
 * would, else the cast is invalid.
 */
CastKind implicitCastFrom(SemanticPass pass, ParamType from, ParamType to) {
	// A reference needs something with an address to bind to.
	if (to.isRef && !from.isRef) {
		return CastKind.Invalid;
	}

	auto f = from.getType();
	auto t = to.getType();
	auto kind = implicitCastFrom(pass, f, t);
	if (!to.isRef || kind == CastKind.Exact) {
		return kind;
	}

	// Only a value of the same representation can be seen as another type.
	if (kind < CastKind.Bit) {
		return CastKind.Invalid;
	}

	auto fq = f.getCanonical().qualifier;
	auto tq = t.getCanonical().qualifier;
	return canBind(fq, tq) ? kind : CastKind.Invalid;
}

CastKind explicitCastFrom(SemanticPass pass, Type from, Type to) {
	return ExplicitCaster(pass, to).castFrom(from);
}

private:

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

Expression buildCast(bool isExplicit)(
	SemanticPass pass,
	Location location,
	Type to,
	Expression e,
) in(e, "Expression must not be null") {
	auto value = Value.fromExpression(e);
	auto casted = buildCast!isExplicit(pass, location, to, value);
	if (casted == value) {
		return e;
	}

	// A constant keeps the location of the literal it comes from.
	auto isLiteral = value.isConstant() && !value.hasAddress();
	return casted.getExpression(isLiteral ? e.location : location);
}

Value buildCast(bool isExplicit)(SemanticPass pass, Location location,
                                 ParamType to, Value value) {
	auto type = to.getType();
	return to.isRef
		? buildReference!isExplicit(pass, location, type, value)
		: buildCast!isExplicit(pass, location, type, value);
}

/**
 * A reference refers to the value, so the result is the value seen as the
 * type to, with its address, if the reference can bind to it.
 */
Value buildReference(bool isExplicit)(SemanticPass pass, Location location,
                                      Type to, Value value) {
	import std.format;

	// Only a value with an address can be referred to.
	if (!value.hasAddress()) {
		return value.getError(
			location,
			format!"Can't bind a value without an address to ref %s."(
				to.toString(pass.context))
		);
	}

	auto kind = Caster!isExplicit(pass, to).castFrom(value.type);
	if (kind == CastKind.Exact) {
		return value;
	}

	// Only a value of the same representation can be seen as another type.
	if (kind >= CastKind.Bit) {
		auto fq = value.type.getCanonical().qualifier;
		auto tq = to.getCanonical().qualifier;
		if (canBind(fq, tq)) {
			return castAddress(location, kind, to, value);
		}
	}

	return value.getError(
		location,
		format!"Can't bind %s to ref %s."(value.type.toString(pass.context),
		                                  to.toString(pass.context))
	);
}

/**
 * Whether a reference can refer to a value with a cast to the same
 * representation, from being the qualifier of the value and to the one of the
 * reference. A reference is a pointer to the value, so it follows the same
 * rules: the qualifier can change as an implicit conversion allows, as long
 * as nothing can be written through the reference.
 */
bool canBind(TypeQualifier from, TypeQualifier to) {
	return !to.isWritable() && canConvert(from, to);
}

Value buildCast(bool isExplicit)(SemanticPass pass, Location location, Type to,
                                 Value value) {
	// Polysemous expressions and array literals are rvalues, so
	// a constant or a value that has an address is neither.
	auto rvalue =
		(value.isConstant() || value.hasAddress()) ? null : value.expression;

	// If the expression is polysemous, we try the several meaning and
	// exclude the ones that make no sense.
	if (auto asPolysemous = cast(PolysemousExpression) rvalue) {
		Expression casted;
		foreach (candidate; asPolysemous.expressions) {
			candidate = buildCast!isExplicit(pass, location, to, candidate);

			import d.ir.error;
			if (cast(ErrorExpression) candidate) {
				continue;
			}

			if (casted) {
				return value.getError(location, "Ambiguous");
			}

			casted = candidate;
		}

		if (casted) {
			return Value.withValue(casted);
		}

		return value.getError(location, "No match found");
	}

	// When casting an array literal, we try to push down the
	// cast to each element of the literal.
	if (auto al = cast(ArrayLiteral) rvalue) {
		switch (to.kind) with (TypeKind) {
			case Array:
				if (al.values.length != to.size) {
					return
						value.getError(al.location, "Incorrect element count");
				}

				goto case;

			case Slice:
				import std.algorithm, std.array;
				auto et = to.element;
				auto values = al
					.values
					.map!(v => buildCast!isExplicit(pass, location, et, v))
					.array();
				return Value
					.withValue(build!ArrayLiteral(al.location, to, values));

			default:
				break;
		}
	}

	// D-style string literals can be implicitely converted to C-style ones.
	import d.ir.constant;
	auto constant =
		(value.isConstant() && !value.hasAddress()) ? value.constant : null;

	if (auto s = cast(StringConstant) constant) {
		if (to.kind == TypeKind.Pointer
			    && implicitCastFrom(pass, value.type.element, to.element)
				    >= CastKind.Qual) {
			return Value.withValue(new CStringConstant(s.value));
		}
	}

	auto kind = Caster!(isExplicit, delegate CastKind(c, t) {
		alias T = typeof(t);
		static if (is(T : Aggregate)) {
			assert(value.type.getCanonical().isAggregate(),
			       "alias this ony works on aggregates.");

			static struct AliasThisResult {
				Expression expr;
				CastKind level;
			}

			auto level = CastKind.Invalid;
			enum InvalidResult = AliasThisResult(null, CastKind.Invalid);

			import d.semantic.aliasthis;
			import std.algorithm;
			auto results = AliasThisResolver!((identified) {
				alias T = typeof(identified);
				static if (is(T : Expression)) {
					auto oldValue = value;
					scope(exit) value = oldValue;
					value = Value.withValue(identified);

					// XXX: Use buildCast?
					auto cLevel = c.subCast(identified.type, to);
					if (cLevel == CastKind.Invalid || cLevel < level) {
						return InvalidResult;
					}

					level = cLevel;
					return AliasThisResult(identified, cLevel);
				} else {
					return InvalidResult;
				}
			})(pass).resolve(value.getExpression(location), t)
			        .filter!(r => r.level == level);

			if (level == CastKind.Invalid) {
				return CastKind.Invalid;
			}

			Expression candidate;
			foreach (r; results) {
				if (candidate !is null) {
					return CastKind.Invalid;
				}

				candidate = r.expr;
			}

			assert(candidate,
			       "if no candidate are found, level should be Invalid");

			value = Value.withValue(candidate);
			return level;
		} else static if (is(T : BuiltinType)) {
			auto to = c.to;
			if (to.kind != TypeKind.Builtin
				    || !canConvertToIntegral(to.builtin)) {
				return CastKind.Invalid;
			}

			assert(getSize(to.builtin) < getSize(t));

			import d.semantic.vrp;
			return ValueRangePropagator!uint(pass).canFit(value, to)
				? CastKind.Trunc
				: CastKind.Invalid;
		} else {
			return CastKind.Invalid;
		}
	})(pass, to).castFrom(value.type);

	// The value already has the right type.
	if (kind == CastKind.Exact) {
		return value;
	}

	// A cast of a constant is a constant, unless it needs to inspect the
	// value at runtime.
	bool isConstantCast = kind != CastKind.Invalid && kind != CastKind.Down;
	if (constant !is null && isConstantCast) {
		return Value.withValue(new CastConstant(kind, to, constant));
	}

	// When a reference could bind to the value, the cast commutes with the
	// load: perform it on the address instead, and the value remains
	// addressable. The value is converted, so it must still be accessed as it
	// needs to be: whether it is shared cannot change.
	if (kind >= CastKind.Bit && value.hasAddress()) {
		auto fq = value.type.getCanonical().qualifier;
		auto tq = to.getCanonical().qualifier;
		if (fq.isShared() == tq.isShared() && canBind(fq, tq)) {
			return castAddress(location, kind, to, value);
		}
	}

	if (kind == CastKind.Invalid) {
		if (to.kind == TypeKind.Error) {
			return Value.withValue(to.error.constant);
		}

		import std.format;
		return value.getError(
			location,
			format!"Can't cast %s to %s."(value.type.toString(pass.context),
			                              to.toString(pass.context)),
		);
	}

	assert(kind != CastKind.Exact, "Exact casts are handled above.");
	return Value.withValue(
		new CastExpression(location, kind, to, value.getExpression(location)));
}

/**
 * The value seen as the type to, at the same address. A constant address
 * remains a constant.
 */
Value castAddress(Location location, CastKind kind, Type to, Value value) {
	auto type = to.getPointer();
	auto address = value.getAddress(location);
	if (address.isConstant()) {
		import d.ir.constant;
		return
			Value.withAddress(new CastConstant(kind, type, address.constant));
	}

	return Value.withAddress(
		new CastExpression(location, kind, type, address.expression));
}

alias ExplicitCaster = Caster!true;
alias ImplicitCaster = Caster!false;

struct Caster(bool isExplicit, alias bailoutOverride = null) {
	// XXX: Used only to get to super class, should probably go away.
	private SemanticPass pass;
	alias pass this;

	Type to;

	this(SemanticPass pass, Type to) {
		this.pass = pass;
		this.to = to;
	}

	enum hasBailoutOverride = !is(typeof(bailoutOverride) : typeof(null));

	CastKind bailout(T)(T t) {
		static if (hasBailoutOverride) {
			return bailoutOverride(this, t);
		} else {
			return CastKind.Invalid;
		}
	}

	CastKind castFrom(Type from) {
		from = from.getCanonical();
		to = to.getCanonical();

		if (from == to) {
			return CastKind.Exact;
		}

		// The visitors do not consider qualifiers, so a cast to what only
		// differs by its qualifier is a qualifier cast.
		auto kind = from.accept(this);
		return (kind == CastKind.Exact && from.qualifier != to.qualifier)
			? CastKind.Qual
			: kind;
	}

	CastKind subCast(Type from, Type to) {
		return Caster!isExplicit(pass, to).castFrom(from);
	}

	/**
	 * Through an indirection, the original and the converted types refer to
	 * the same data, so anything written through one must be valid for the
	 * other. The qualifier of what is referred to can only become const, and
	 * as long as it is writable, nothing below it can change, or one could
	 * store something that breaks the guarantees of the original type. An
	 * explicit cast can change any qualifier.
	 */
	CastKind castReferred(Type from, Type to) {
		auto kind = subCast(from, to);
		if (isExplicit || kind == CastKind.Exact) {
			return kind;
		}

		if (!canConvert(from.qualifier, to.qualifier)) {
			return CastKind.Invalid;
		}

		return to.qualifier.isWritable() ? CastKind.Invalid : kind;
	}

	/**
	 * A context is bound with the function and given back to it unchanged,
	 * so the function never sees another context than the one it was bound
	 * with. What the context is can be hidden, as long as it is passed the
	 * same way, even explicitly, or the function would not find it.
	 */
	CastKind castContext(ParamType from, ParamType to) {
		auto f = from.isRef ? from.getType().getPointer() : from.getType();
		auto t = to.isRef ? to.getType().getPointer() : to.getType();

		auto k = ExplicitCaster(pass, t).castFrom(f);
		if (k >= CastKind.Bit) {
			return k;
		}

		// Everything passed as a pointer is passed the same way.
		return (f.hasPointerABI() && t.hasPointerABI())
			? CastKind.Bit
			: CastKind.Invalid;
	}

	CastKind castParam(ParamType from, ParamType to) {
		if (from.isRef != to.isRef) {
			return CastKind.Invalid;
		}

		// A ref parameter refers to the data it is given.
		return from.isRef
			? castReferred(from.getType(), to.getType())
			: subCast(from.getType(), to.getType());
	}

	CastKind visit(BuiltinType t) {
		if (isExplicit && to.kind == TypeKind.Enum) {
			to = to.getCanonicalAndPeelEnum();
			auto k = visit(t);
			return (k == CastKind.Exact) ? CastKind.Bit : k;
		}

		// Can cast typeof(null) to class, pointer and function.
		if (t == BuiltinType.Null && to.hasPointerABI()) {
			return CastKind.Bit;
		}

		// Can explicitely cast integral to pointer.
		if (isExplicit
			    && (to.kind == TypeKind.Pointer && canConvertToIntegral(t))) {
			if (isIntegral(t) && isSigned(t)) {
				return CastKind.SignedToPointer;
			}

			return CastKind.UnsignedToPointer;
		}

		if (to.kind != TypeKind.Builtin) {
			return CastKind.Invalid;
		}

		auto bt = to.builtin;
		if (t == bt) {
			return CastKind.Exact;
		}

		final switch (t) with (BuiltinType) {
			case None:
			case Void:
				return CastKind.Invalid;

			case Bool:
				if (isIntegral(bt)) {
					return CastKind.UPad;
				}

				return CastKind.Invalid;

			case Char:
				t = integralOfChar(t);
				goto case Ubyte;

			case Wchar:
				t = integralOfChar(t);
				goto case Ushort;

			case Dchar:
				t = integralOfChar(t);
				goto case Uint;

			case Byte, Ubyte, Short, Ushort, Int, Uint, Long, Ulong, Cent,
			     Ucent:
				if (isExplicit && bt == Bool) {
					return CastKind.IntToBool;
				}

				if (!isIntegral(bt)) {
					return CastKind.Invalid;
				}

				auto ut = unsigned(t);
				bt = unsigned(bt);
				if (ut == bt) {
					return CastKind.Bit;
				}

				if (ut < bt) {
					return isSigned(t) ? CastKind.SPad : CastKind.UPad;
				}

				static if (isExplicit) {
					return CastKind.Trunc;
				} else {
					// This will trigger VRP.
					return bailout(t);
				}

			case Float, Double, Real:
				assert(0, "Floating point casts are not implemented");

			case Null:
				if (isExplicit && canConvertToIntegral(bt)) {
					return CastKind.PointerToInt;
				}

				return CastKind.Invalid;
		}
	}

	CastKind visitPointerOf(Type t) {
		// You can explicitely cast pointer to class, function.
		if (isExplicit && to.kind != TypeKind.Pointer && to.hasPointerABI()) {
			return CastKind.Bit;
		}

		// It is also possible to cast to integral explicitely.
		if (isExplicit && to.kind == TypeKind.Builtin) {
			auto bt = to.builtin;
			if (bt == BuiltinType.Bool) {
				return CastKind.PointerToBool;
			}

			// We might want to ensure that the size is right and
			// refuse to cast if it isn't. This would avoid bugs
			// due to unintended truncations.
			if (canConvertToIntegral(bt)) {
				return CastKind.PointerToInt;
			}
		}

		if (to.kind != TypeKind.Pointer) {
			return CastKind.Invalid;
		}

		auto e = to.element.getCanonical();

		// Cast to void* is kind of special.
		if (e.kind == TypeKind.Builtin && e.builtin == BuiltinType.Void) {
			return (isExplicit || canConvert(t.qualifier, e.qualifier))
				? CastKind.Bit
				: CastKind.Invalid;
		}

		auto subCast = castReferred(t, e);
		switch (subCast) with (CastKind) {
			case Qual:
				return Qual;

			case Exact:
				return Exact;

			case Bit:
				return Bit;

			default:
				return isExplicit ? Bit : Invalid;
		}
	}

	CastKind visitSliceOf(Type t) {
		if (to.kind != TypeKind.Slice) {
			return CastKind.Invalid;
		}

		auto e = to.element.getCanonical();

		auto subCast = castReferred(t, e);
		switch (subCast) with (CastKind) {
			case Qual:
				return Qual;

			case Exact:
				return Exact;

			case Bit:
				return Bit;

			default:
				return isExplicit ? Bit : Invalid;
		}
	}

	CastKind visitArrayOf(uint size, Type t) {
		if (to.kind != TypeKind.Array) {
			return CastKind.Invalid;
		}

		if (size != to.size) {
			return CastKind.Invalid;
		}

		auto e = to.element.getCanonical();

		// The elements are stored in the array, so their qualifier
		// can change just like the qualifier of the array itself.
		// Casting each element is not supported.
		auto subCast = subCast(t, e);
		return subCast >= CastKind.Bit ? subCast : CastKind.Invalid;
	}

	CastKind visit(Struct s) {
		if (to.kind == TypeKind.Struct) {
			if (to.dstruct is s) {
				return CastKind.Exact;
			}
		}

		return bailout(s);
	}

	private auto castClass(Class from, Class to) {
		if (from is to) {
			return CastKind.Exact;
		}

		scheduler.require(to, Step.Signed);
		auto tp = to.primaries;
		auto tDepth = tp.length;

		if (tDepth == 0) {
			// This is Object
			return CastKind.Bit;
		}

		scheduler.require(from, Step.Signed);
		auto fp = from.primaries;
		auto fDepth = fp.length;

		if (isExplicit && fDepth == 0) {
			// We are casting from object, this is a downcast.
			return CastKind.Down;
		}

		if (fDepth > tDepth && fp[tDepth - 1] is to) {
			// This is an upcast.
			return CastKind.Bit;
		}

		if (isExplicit && fDepth < tDepth && tp[fDepth - 1] is from) {
			// This is a downcast.
			return CastKind.Down;
		}

		return CastKind.Invalid;
	}

	CastKind visit(Class c) {
		if (isExplicit && to.kind == TypeKind.Pointer) {
			auto et = to.element.getCanonical();
			if (et.kind == TypeKind.Builtin && et.builtin == BuiltinType.Void) {
				return CastKind.Bit;
			}
		}

		if (to.kind == TypeKind.Class) {
			auto kind = castClass(c, to.dclass);
			if (kind > CastKind.Invalid) {
				return kind;
			}
		}

		return bailout(c);
	}

	CastKind visit(Enum e) {
		if (to.kind == TypeKind.Enum) {
			if (e is to.denum) {
				return CastKind.Exact;
			}
		}

		// Automagically promote to base type.
		return castFrom(e.type);
	}

	CastKind visit(TypeAlias a) {
		return castFrom(a.type);
	}

	CastKind visit(Interface i) {
		return CastKind.Invalid;
	}

	CastKind visit(Union u) {
		return (to.kind == TypeKind.Union && to.dunion is u)
			? CastKind.Exact
			: CastKind.Invalid;
	}

	CastKind visit(Function f) {
		assert(0, "Cast to context type do not make any sense.");
	}

	CastKind visit(Type[] splat) {
		assert(0, "Cast to sequence type do not make any sense.");
	}

	CastKind visit(FunctionType f) {
		if (to.kind == TypeKind.Pointer && f.contexts.length == 0) {
			auto e = to.element.getCanonical();
			static if (isExplicit) {
				return CastKind.Bit;
			} else if (e.kind == TypeKind.Builtin
				           && e.builtin == BuiltinType.Void) {
				// FIXME: qualifier.
				return CastKind.Bit;
			} else {
				return CastKind.Invalid;
			}
		}

		if (to.kind != TypeKind.Function) {
			return CastKind.Invalid;
		}

		auto tf = to.asFunctionType();

		if (f.contexts.length != tf.contexts.length) {
			return CastKind.Invalid;
		}

		auto k = CastKind.Exact;

		import std.algorithm, std.range;
		foreach (fromc, toc; lockstep(f.contexts, tf.contexts)) {
			k = min(k, castContext(fromc, toc));
		}

		if (k == CastKind.Invalid) {
			return CastKind.Invalid;
		}

		enum onFail = isExplicit ? CastKind.Bit : CastKind.Invalid;

		if (f.parameters.length != tf.parameters.length) {
			return onFail;
		}

		if (f.isVariadic != tf.isVariadic) {
			return onFail;
		}

		if (f.linkage != tf.linkage) {
			return onFail;
		}

		auto kr = castParam(f.returnType, tf.returnType);
		if (kr < CastKind.Bit) {
			return onFail;
		}

		k = min(k, kr);

		foreach (fromp, top; lockstep(f.parameters, tf.parameters)) {
			// Parameters are contrevariant.
			auto kp = castParam(top, fromp);
			if (kp < CastKind.Bit) {
				return onFail;
			}

			k = min(k, kp);
		}

		return (k < CastKind.Exact) ? CastKind.Bit : CastKind.Exact;
	}

	CastKind visit(Pattern p) {
		assert(0, "Pattern cannot be casted.");
	}

	import d.ir.error;
	CastKind visit(CompileError e) {
		return CastKind.Invalid;
	}
}

unittest {
	import d.ir.constant;

	auto pass = SemanticPass.getTestSemanticPass();

	auto base = Location.init.start;
	auto literalLocation = base.getWithOffsets(1, 2);
	auto castLocation = base.getWithOffsets(3, 4);

	auto cstring =
		Type.get(BuiltinType.Char).getPointer(TypeQualifier.Immutable);

	// A string literal converted to a C string keeps its location.
	auto literal =
		new ConstantExpression(literalLocation, new StringConstant("abc"));
	auto fromExpression = cast(ConstantExpression)
		buildImplicitCast(pass, castLocation, cstring, literal);
	assert(fromExpression !is null);
	assert(fromExpression.location == literalLocation);
	assert(cast(CStringConstant) fromExpression.value !is null);

	// A string constant has no location: the cast's is used.
	auto fromConstant =
		buildImplicitCast(pass, castLocation, cstring,
		                  Value.withValue(new StringConstant("abc")));
	assert(fromConstant.isConstant());
	assert(cast(CStringConstant) fromConstant.constant !is null);

	// A string literal is immutable(char[]), and string is
	// immutable(char)[], so this is a qualifier cast.
	auto literalType =
		Type.get(BuiltinType.Char).getSlice(TypeQualifier.Immutable)
		    .qualify(TypeQualifier.Immutable);
	auto stringType =
		Type.get(BuiltinType.Char).qualify(TypeQualifier.Immutable).getSlice();
	auto str = new StringConstant("abc");
	assert(str.type == literalType);

	auto qualified =
		buildImplicitCast(pass, castLocation, stringType, Value.withValue(str));
	assert(qualified.isConstant());

	auto cc = cast(CastConstant) qualified.constant;
	assert(cc !is null);
	assert(cc.kind == CastKind.Qual);
	assert(cc.type == stringType);
	assert(cc.value is str);

	// An integer cast to a pointer is a constant too.
	auto zero = new IntegerConstant(0, BuiltinType.Ulong);
	auto voidPtr = Type.get(BuiltinType.Void).getPointer();
	auto fromInt =
		buildExplicitCast(pass, castLocation, voidPtr, Value.withValue(zero));
	assert(fromInt.isConstant());

	auto ic = cast(CastConstant) fromInt.constant;
	assert(ic !is null);
	assert(ic.kind == CastKind.UnsignedToPointer);
	assert(ic.value is zero);
}

unittest {
	import source.name;

	auto pass = SemanticPass.getTestSemanticPass();
	auto location = Location.init;

	auto i = Type.get(BuiltinType.Int);
	auto ci = i.qualify(TypeQualifier.Const);

	Value addressOf(Type t) {
		auto v = new Variable(location, t, BuiltinName!"", null);
		return Value.withAddress(new VariableExpression(location, v));
	}

	CastKind addressCastKind(Value v) {
		auto c = cast(CastExpression) v.getAddress(location).expression;
		return c is null ? CastKind.Invalid : c.kind;
	}

	// The same type: the value is returned as is.
	auto same = addressOf(i);
	assert(buildImplicitCast(pass, location, i, same) == same);

	// A qualifier that converts: the address is cast.
	auto toConst = buildImplicitCast(pass, location, ci, addressOf(i));
	assert(toConst.hasAddress());
	assert(toConst.type == ci);
	assert(addressCastKind(toConst) == CastKind.Qual);

	// A qualifier that does not convert cannot be done on the address, even
	// explicitly, so the value is cast after being loaded.
	auto from = addressOf(i.getSlice(TypeQualifier.Const));
	auto to = ci.getSlice();

	auto explicit = buildExplicitCast(pass, location, to, from);
	assert(!explicit.hasAddress());
	assert(explicit.type == to);

	auto implicit = buildImplicitCast(pass, location, to, from);
	assert(!implicit.hasAddress());
	assert(implicit.type == to);

	// Neither can dropping shared.
	auto si = i.qualify(TypeQualifier.Shared);
	assert(!buildImplicitCast(pass, location, i, addressOf(si)).hasAddress());
	assert(!buildExplicitCast(pass, location, i, addressOf(si)).hasAddress());

	// The value can be seen as another type of the same size, as long as it
	// cannot be written to.
	auto u = Type.get(BuiltinType.Uint);
	auto cu = u.qualify(TypeQualifier.Const);
	auto toBits = buildImplicitCast(pass, location, cu, addressOf(i));
	assert(toBits.hasAddress());
	assert(toBits.type == cu);
	assert(addressCastKind(toBits) == CastKind.Bit);

	assert(!buildImplicitCast(pass, location, u, addressOf(i)).hasAddress());

	// It still cannot drop shared.
	auto csu = cu.qualify(TypeQualifier.Shared);
	auto toSharedBits = buildImplicitCast(pass, location, csu, addressOf(si));
	assert(toSharedBits.hasAddress());
	assert(addressCastKind(toSharedBits) == CastKind.Bit);

	assert(!buildImplicitCast(pass, location, cu, addressOf(si)).hasAddress());

	// A value of another size cannot be seen in place.
	auto cl = Type.get(BuiltinType.Long).qualify(TypeQualifier.Const);
	assert(!buildImplicitCast(pass, location, cl, addressOf(i)).hasAddress());
}

unittest {
	auto pass = SemanticPass.getTestSemanticPass();

	auto i = Type.get(BuiltinType.Int);
	auto ci = i.qualify(TypeQualifier.Const);
	auto si = i.qualify(TypeQualifier.Shared);

	// An exact cast is a cast to the very same type.
	assert(implicitCastFrom(pass, i, i) == CastKind.Exact);
	assert(
		implicitCastFrom(pass, i.getArray(2), i.getArray(2)) == CastKind.Exact);

	// Changing only the qualifier is a qualifier cast, whatever the type.
	assert(implicitCastFrom(pass, i, ci) == CastKind.Qual);
	assert(implicitCastFrom(pass, i, si) == CastKind.Qual);
	assert(
		implicitCastFrom(pass, i.getPointer(), ci.getPointer()) == CastKind.Qual
	);
	assert(
		implicitCastFrom(pass, i.getArray(2), ci.getArray(2)) == CastKind.Qual);

	// What a pointer points to cannot lose its qualifier implicitly.
	assert(implicitCastFrom(pass, ci.getPointer(), i.getPointer())
		== CastKind.Invalid);
	assert(implicitCastFrom(pass, si.getPointer(), i.getPointer())
		== CastKind.Invalid);
}

unittest {
	auto pass = SemanticPass.getTestSemanticPass();

	auto i = Type.get(BuiltinType.Int);
	auto l = Type.get(BuiltinType.Long);
	auto ci = i.qualify(TypeQualifier.Const);
	auto si = i.qualify(TypeQualifier.Shared);
	auto ii = i.qualify(TypeQualifier.Immutable);
	auto csi = si.qualify(TypeQualifier.Const);

	auto test(Type from, ParamKind fk, Type to, ParamKind tk) {
		return
			implicitCastFrom(pass, from.getParamType(fk), to.getParamType(tk));
	}

	// A value is cast the same way, whether it has an address or not.
	foreach (k; [ParamKind.Regular, ParamKind.Final, ParamKind.Ref]) {
		assert(test(i, k, i, ParamKind.Regular) == CastKind.Exact);
		assert(test(i, k, ci, ParamKind.Regular) == CastKind.Qual);
		assert(test(ci, k, i, ParamKind.Regular) == CastKind.Qual);
		assert(
			test(i, k, l, ParamKind.Regular) == implicitCastFrom(pass, i, l));
	}

	// A reference needs something with an address to bind to.
	assert(test(i, ParamKind.Regular, i, ParamKind.Ref) == CastKind.Invalid);
	assert(test(i, ParamKind.Final, i, ParamKind.Ref) == CastKind.Invalid);
	assert(test(i, ParamKind.Ref, i, ParamKind.Ref) == CastKind.Exact);

	// It can view it as a pointer would.
	assert(test(i, ParamKind.Ref, ci, ParamKind.Ref) == CastKind.Qual);
	assert(test(ii, ParamKind.Ref, csi, ParamKind.Ref) == CastKind.Qual);

	// But it cannot write what the value doesn't allow.
	assert(test(ci, ParamKind.Ref, i, ParamKind.Ref) == CastKind.Invalid);
	assert(test(i, ParamKind.Ref, si, ParamKind.Ref) == CastKind.Invalid);
	assert(test(ii, ParamKind.Ref, si, ParamKind.Ref) == CastKind.Invalid);

	// Nor can it see a value as a value of another size.
	assert(test(i, ParamKind.Ref, l, ParamKind.Ref) == CastKind.Invalid);
}

unittest {
	auto pass = SemanticPass.getTestSemanticPass();

	auto i = Type.get(BuiltinType.Int);
	auto u = Type.get(BuiltinType.Uint);
	auto ci = i.qualify(TypeQualifier.Const);
	auto ii = i.qualify(TypeQualifier.Immutable);
	auto si = i.qualify(TypeQualifier.Shared);
	auto csi = i.qualify(TypeQualifier.ConstShared);

	CastKind kind(Type from, Type to) {
		return explicitCastFrom(pass, from, to);
	}

	// An explicit cast can change any qualifier, at any level.
	assert(kind(ci, i) == CastKind.Qual);
	assert(kind(i, si) == CastKind.Qual);

	auto pi = i.getPointer();
	assert(kind(ci.getPointer(), pi) == CastKind.Qual);
	assert(kind(ii.getPointer(), pi) == CastKind.Qual);
	assert(kind(si.getPointer(), pi) == CastKind.Qual);
	assert(kind(pi, ii.getPointer()) == CastKind.Qual);
	assert(kind(ci.getPointer(), ii.getPointer()) == CastKind.Qual);
	assert(kind(csi.getPointer(), si.getPointer()) == CastKind.Qual);

	auto ppi = pi.getPointer();
	auto ppci = ci.getPointer().getPointer();
	assert(kind(ppi, ppci) == CastKind.Qual);
	assert(kind(ppci, ppi) == CastKind.Qual);
	assert(kind(ii.getPointer().getPointer(), ppci) == CastKind.Qual);
	assert(kind(si.getPointer().getPointer(), csi.getPointer().getPointer())
		== CastKind.Qual);

	assert(kind(ci.getSlice(), i.getSlice()) == CastKind.Qual);
	assert(kind(i.getSlice(), ii.getSlice()) == CastKind.Qual);
	assert(
		kind(i.getSlice().getSlice(), ci.getSlice().getSlice()) == CastKind.Qual
	);
	assert(kind(pi.getSlice(), ci.getPointer().getSlice()) == CastKind.Qual);

	assert(kind(ci.getArray(2).getPointer(), i.getArray(2).getPointer())
		== CastKind.Qual);
	assert(kind(ci.getPointer().getArray(2), pi.getArray(2)) == CastKind.Qual);

	assert(kind(pi.getArray(2, TypeQualifier.Const), pi.getArray(2))
		== CastKind.Qual);

	// Changing more than qualifiers is not a qualifier cast.
	assert(kind(pi, u.getPointer()) == CastKind.Bit);
	assert(kind(ci.getPointer(), u.getPointer()) == CastKind.Bit);
	assert(kind(ppci, u.getPointer().getPointer()) == CastKind.Bit);
	assert(kind(ci.getSlice(), u.getSlice()) == CastKind.Bit);
}

unittest {
	auto pass = SemanticPass.getTestSemanticPass();

	auto i = Type.get(BuiltinType.Int);
	auto v = Type.get(BuiltinType.Void);

	CastKind kind(Type from, Type to) {
		return implicitCastFrom(pass, from, to);
	}

	Type pointerTo(Type t, TypeQualifier q) {
		return t.qualify(q).getPointer();
	}

	// Nothing is written as void, so a pointer can point to anything as void,
	// as long as the qualifier converts.
	auto qualifiers =
		[TypeQualifier.Mutable, TypeQualifier.Const, TypeQualifier.Immutable,
		 TypeQualifier.Shared, TypeQualifier.ConstShared];
	foreach (q; qualifiers) {
		assert(kind(pointerTo(i, q), pointerTo(v, q)) == CastKind.Bit);
	}

	auto pi = i.getPointer();
	auto pv = v.getPointer();
	assert(kind(pi, pointerTo(v, TypeQualifier.Const)) == CastKind.Bit);
	assert(kind(pointerTo(i, TypeQualifier.Immutable),
	            pointerTo(v, TypeQualifier.ConstShared)) == CastKind.Bit);
	assert(kind(pointerTo(i, TypeQualifier.Const), pv) == CastKind.Invalid);
	assert(kind(pointerTo(i, TypeQualifier.Shared), pv) == CastKind.Invalid);
	assert(kind(pi, pointerTo(v, TypeQualifier.Shared)) == CastKind.Invalid);

	// What is pointed to can itself be a pointer.
	auto ppi = pi.getPointer();
	assert(kind(ppi, pv) == CastKind.Bit);

	// Something else that can be written could hold something else than
	// what is pointed to.
	assert(kind(ppi, pv.getPointer()) == CastKind.Invalid);
	assert(kind(ppi, pointerTo(pv, TypeQualifier.Const)) == CastKind.Bit);

	// Slices of void have a different length, so they are not the same data
	// seen as a different type.
	assert(kind(i.getSlice(), v.getSlice()) == CastKind.Invalid);
}

unittest {
	auto pass = SemanticPass.getTestSemanticPass();

	auto i = Type.get(BuiltinType.Int);
	auto u = Type.get(BuiltinType.Uint);
	auto l = Type.get(BuiltinType.Long);
	auto vp = Type.get(BuiltinType.Void).getPointer();

	auto ret = i.getParamType(ParamKind.Regular);
	Type delegateOf(ParamType context) {
		return FunctionType(Linkage.D, ret, [context], false).getDelegate()
		                                                     .getType();
	}

	auto byRef = delegateOf(i.getParamType(ParamKind.Ref));
	auto byPointer = delegateOf(vp.getParamType(ParamKind.Regular));
	auto bySlice = delegateOf(i.getSlice().getParamType(ParamKind.Final));
	auto byInt = delegateOf(i.getParamType(ParamKind.Final));
	auto byUint = delegateOf(u.getParamType(ParamKind.Final));
	auto byLong = delegateOf(l.getParamType(ParamKind.Final));

	// The context is given back unchanged to the function, so what it is can
	// be hidden as long as it is passed the same way.
	assert(implicitCastFrom(pass, byRef, byPointer) == CastKind.Bit);
	assert(implicitCastFrom(pass, byPointer, byRef) == CastKind.Bit);
	assert(implicitCastFrom(pass, byInt, byUint) == CastKind.Bit);
	assert(implicitCastFrom(pass, byInt, byInt) == CastKind.Exact);

	// Otherwise, the function would not find it, even explicitly.
	assert(implicitCastFrom(pass, bySlice, byPointer) == CastKind.Invalid);
	assert(explicitCastFrom(pass, bySlice, byPointer) == CastKind.Invalid);
	assert(explicitCastFrom(pass, byInt, byLong) == CastKind.Invalid);
	assert(explicitCastFrom(pass, byInt, byPointer) == CastKind.Invalid);
}
