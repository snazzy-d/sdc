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

CastKind implicitCastFrom(SemanticPass pass, Type from, Type to) {
	return ImplicitCaster(pass, to).castFrom(from);
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
	return buildCast!isExplicit(pass, location, to, Value.withValue(e))
		.getExpression(location);
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
	auto ce = cast(ConstantExpression) rvalue;
	auto constant = ce !is null
		? ce.value
		: (value.isConstant() && !value.hasAddress()) ? value.constant : null;

	if (auto s = cast(StringConstant) constant) {
		if (to.kind == TypeKind.Pointer
			    && implicitCastFrom(pass, value.type.element, to.element)
				    >= CastKind.Qual) {
			auto cs = new CStringConstant(s.value);

			// Keep the location of the literal, if there is one.
			return ce is null
				? Value.withValue(cs)
				: Value.withValue(new ConstantExpression(ce.location, cs));
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

	// A cast of a constant is a constant, unless it needs to inspect the
	// value at runtime.
	bool isConstantCast = kind != CastKind.Invalid && kind != CastKind.Exact
		&& kind != CastKind.Down;
	if (constant !is null && isConstantCast) {
		return Value.withValue(new CastConstant(kind, to, constant));
	}

	// A cast that does not change the bits of the value
	// commutes with the load: perform it on the address
	// instead, and the value remains addressable. This is
	// only sound if the qualifier of the value converts to
	// the target's, or the load would not honor it.
	if (value.hasAddress() && kind >= CastKind.Qual
		    && canConvert(value.type.getCanonical().qualifier,
		                  to.getCanonical().qualifier)) {
		auto addr = value.getAddress(location).getExpression(location);
		auto ptr = to.getPointer();

		// The address is an rvalue, so the qualifier of the pointer
		// itself does not matter, only what it points to.
		if (addr.type.getCanonical().unqual() == ptr.getCanonical().unqual()) {
			return value;
		}

		return Value.withAddress(
			new CastExpression(location, CastKind.Qual, ptr, addr));
	}

	switch (kind) with (CastKind) {
		case Exact:
			// FIXME: Because we don't cast type qualifier the proper
			// way, we need to make sure they match.
			auto e = value.getExpression(location);
			e.type = e.type.qualify(to.qualifier);
			return Value.withValue(e);

		default:
			return Value.withValue(
				new CastExpression(location, kind, to,
				                   value.getExpression(location)));

		case Invalid:
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

	// FIXME: handle qualifiers.
	CastKind castFrom(Type from) {
		from = from.getCanonical();
		to = to.getCanonical();

		if (from == to) {
			return CastKind.Exact;
		}

		return from.accept(this);
	}

	CastKind subCast(Type from, Type to) {
		return Caster!isExplicit(pass, to).castFrom(from);
	}

	CastKind castParam(ParamType from, ParamType to) {
		if (from.isRef != to.isRef) {
			return CastKind.Invalid;
		}

		auto k = subCast(from.getType(), to.getType());
		if (from.isRef && k < CastKind.Qual) {
			return CastKind.Invalid;
		}

		return k;
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

		auto subCast = subCast(t, e);
		switch (subCast) with (CastKind) {
			case Qual:
				if (canConvert(t.qualifier, e.qualifier)) {
					return Qual;
				}

				goto default;

			case Exact:
				return Qual;

			case Bit:
				bool canConvert =
					!isExplicit && canConvert(t.qualifier, e.qualifier);
				if (canConvert) {
					return subCast;
				}

				goto default;

			default:
				return isExplicit ? Bit : Invalid;
		}
	}

	CastKind visitSliceOf(Type t) {
		if (to.kind != TypeKind.Slice) {
			return CastKind.Invalid;
		}

		auto e = to.element.getCanonical();

		auto subCast = subCast(t, e);
		switch (subCast) with (CastKind) {
			case Qual:
				if (canConvert(t.qualifier, e.qualifier)) {
					return Qual;
				}

				goto default;

			case Exact:
				return Qual;

			case Bit:
				bool canConvert =
					!isExplicit && canConvert(t.qualifier, e.qualifier);
				if (canConvert) {
					return subCast;
				}

				goto default;

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

		auto subCast = subCast(t, e);
		switch (subCast) with (CastKind) {
			case Qual:
				if (canConvert(t.qualifier, e.qualifier)) {
					return Qual;
				}

				goto default;

			case Exact:
				return Exact;

			case Bit:
				bool canConvert =
					!isExplicit && canConvert(t.qualifier, e.qualifier);
				if (canConvert) {
					return subCast;
				}

				goto default;

			default:
				return isExplicit ? Bit : Invalid;
		}
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

		auto k = castParam(f.returnType, tf.returnType);
		if (k < CastKind.Bit) {
			return onFail;
		}

		import std.range;
		foreach (fromc, toc; lockstep(f.contexts, tf.contexts)) {
			// ref context decay to void*
			if (fromc.isRef && !toc.isRef && toc.kind == TypeKind.Pointer) {
				auto e = toc.getType().element;
				if (e.kind == TypeKind.Builtin
					    && e.builtin == BuiltinType.Void) {
					k = CastKind.Bit;
					continue;
				}
			}

			// Contexts are covariant.
			auto kc = castParam(fromc, toc);
			if (kc < CastKind.Bit) {
				return onFail;
			}

			import std.algorithm;
			k = min(k, kc);
		}

		foreach (fromp, top; lockstep(f.parameters, tf.parameters)) {
			// Parameters are contrevariant.
			auto kp = castParam(top, fromp);
			if (kp < CastKind.Bit) {
				return onFail;
			}

			import std.algorithm;
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

	// A qualifier that does not convert cannot be done on the address,
	// so the value is cast after being loaded.
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
	auto fromShared = buildImplicitCast(pass, location, i, addressOf(si));
	assert(!fromShared.hasAddress());
}
