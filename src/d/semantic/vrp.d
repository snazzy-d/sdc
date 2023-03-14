module d.semantic.vrp;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.semantic.semantic;

import std.traits;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

/**
 * ValueRangePropagator to figure out if it is safe to truncate
 * a value to make it fit in a smaller type.
 *
 * It does so by computing the range of possible values the
 * expression can take and checking if that range fit in a given type.
 *
 * It is only specialized for uint and ulong, as smaller integral type
 * are promoted before any computation to 32bits values and above.
 * As a result, smaller types do not really matter as long as we promote
 * them properly. As a result, ranges computed from improperly promoted
 * expression may be extremely pessimistics.
 */
struct ValueRangePropagator(T) if (is(T == uint) || is(T == ulong)) {
	private SemanticPass pass;
	alias pass this;

	alias VR = ValueRange!T;

	this(SemanticPass pass) {
		this.pass = pass;
	}

	bool canFit(Expression e, Type t)
			in(isValidExpr(e), "VRP expect integral types.") {
		return canFit(e, getBuiltin(t));
	}

	bool canFit(Expression e, BuiltinType t) in {
		assert(isValidExpr(e), "VRP expect integral types.");
		assert(canConvertToIntegral(t), "VRP only supports integral types.");
	} do {
		static canFitDMDMonkeyDance(R)(R r, BuiltinType t) {
			auto mask = cast(R.U) ((1UL << t.getBits()) - 1);

			// Try to fit into the unsigned range.
			auto urange = r.unsigned.normalized;
			if (urange.max <= mask) {
				return true;
			}

			// Try to fit into the signed range.
			auto smask = mask >> 1;
			auto nmask = ~smask;

			auto srange = r.signed.normalized;
			if (srange.min >= nmask && srange.max <= smask) {
				return true;
			}

			// Ho noes, it doesn't fit /o\
			return false;
		}

		return processExpr!canFitDMDMonkeyDance(e, t);
	}

private:
	static asHandlerDMDMonkeyDance(R)(R r) {
		return r.as!T;
	}

	auto processExpr(alias handler = asHandlerDMDMonkeyDance,
	                 A...)(Expression e, A args) {
		import std.algorithm;
		auto s = max(getBuiltin(e.type).getSize(), uint.sizeof);
		if (s == T.sizeof) {
			return handler(visit(e), args);
		}

		switch (s) {
			case uint.sizeof:
				return handler(ValueRangePropagator!uint(pass).visit(e), args);

			case ulong.sizeof:
				return handler(ValueRangePropagator!ulong(pass).visit(e), args);

			default:
				assert(0, "Size not supported by VRP");
		}
	}

	BuiltinType getBuiltin(Type t)
			out(result; canConvertToIntegral(result),
			            "VRP only supports integral types.") {
		t = t.getCanonicalAndPeelEnum();
		if (t.hasPointerABI()) {
			return getBuiltin(pass.object.getSizeT().type);
		}

		assert(t.kind == TypeKind.Builtin, "Invalid type for VRP");
		return t.builtin;
	}

	VR getRange(Type t) {
		return getRange(getBuiltin(t));
	}

	VR getRange(BuiltinType t) in(t.getSize() <= T.sizeof) {
		if (t == BuiltinType.Bool) {
			return VR(0, 1);
		}

		if (isChar(t)) {
			t = integralOfChar(t);
		}

		return ValueRange!ulong(getMin(t), getMax(t)).as!T;
	}

public:
	VR visit(Expression e) in(isValidExpr(e), "VRP expect integral types.") {
		return this.dispatch!(e => getRange(e.type))(e);
	}

	VR visit(BooleanLiteral e) {
		return VR(e.value);
	}

	VR visit(IntegerLiteral e) {
		return ValueRange!ulong(e.value).as!T;
	}

	VR visit(BinaryExpression e) {
		switch (e.op) with (BinaryOp) {
			case Comma, Assign:
				return visit(e.rhs);

			case Add:
				return visit(e.lhs) + visit(e.rhs);

			case Sub:
				return visit(e.lhs) - visit(e.rhs);

			case Mul:
				return visit(e.lhs) * visit(e.rhs);

			case UDiv:
				return visit(e.lhs) / visit(e.rhs);

			case SDiv:
				return (visit(e.lhs).signed / visit(e.rhs).signed).unsigned;

			case URem:
				return visit(e.lhs) % visit(e.rhs);

			case SRem:
				return (visit(e.lhs).signed % visit(e.rhs).signed).unsigned;

			case Or:
				return visit(e.lhs) | visit(e.rhs);

			case And:
				return visit(e.lhs) & visit(e.rhs);

			case Xor:
				return visit(e.lhs) ^ visit(e.rhs);

			case LeftShift:
				return visit(e.lhs) << visit(e.rhs);

			case UnsignedRightShift:
				return visit(e.lhs) >>> visit(e.rhs);

			case SignedRightShift:
				return (visit(e.lhs).signed >> visit(e.rhs).signed).unsigned;

			default:
				assert(0, "Not implemented.");
		}
	}

	VR visit(UnaryExpression e) {
		switch (e.op) with (UnaryOp) {
			case Plus:
				return visit(e.expr);

			case Minus:
				return -visit(e.expr);

			default:
				assert(0, "Not implemented.");
		}
	}

	VR visit(VariableExpression e) {
		auto v = e.var;
		scheduler.require(v, Step.Processed);
		return visit(v);
	}

	VR visit(Variable v) in(v.step >= Step.Processed) {
		return (v.storage == Storage.Enum
				|| v.type.getCanonical().qualifier == TypeQualifier.Immutable)
			? visit(v.value)
			: getRange(v.type);
	}

	VR visit(CastExpression e) {
		final switch (e.kind) with (CastKind) {
			case Invalid:
				assert(0, "Invalid cast");

			case IntToPtr, Down:
				assert(0, "Do not make any sense on integrals");

			case PtrToInt:
				auto t = getBuiltin(e.type);
				return getRange(t);

			case SignedToFloat, UnsignedToFloat:
			case FloatExtend, FloatTrunc:
				assert(0, "VRP not valid on float-yielding casts");

			case FloatToSigned, FloatToUnsigned:
				auto t = getBuiltin(e.type);
				return getRange(t);

			case IntToBool:
				static doTheDMDMonkeyDance(R)(R r) {
					return VR(!r.containsZero, r != R(0));
				}

				return processExpr!doTheDMDMonkeyDance(e.expr);

			case Trunc:
				static doTheDMDMonkeyDance(R)(R r, BuiltinType t) {
					auto signed = isIntegral(t) && isSigned(t);
					auto mask = cast(R.U) ((1UL << t.getBits()) - 1);

					return signed
						? r.signed.trunc(mask).as!T
						: r.trunc(mask).as!T;
				}

				return
					processExpr!doTheDMDMonkeyDance(e.expr, getBuiltin(e.type));

			case UPad:
				auto t = getBuiltin(e.expr.type);
				auto r = processExpr(e.expr);

				auto mask = cast(T) ((1UL << t.getBits()) - 1);
				return r.pad(mask);

			case SPad:
				auto t = getBuiltin(e.expr.type);
				auto r = processExpr(e.expr);

				auto mask = cast(T) ((1UL << t.getBits()) - 1);
				return r.signed.pad(mask).unsigned;

			case Bit, Qual, Exact:
				return visit(e.expr);
		}
	}

	VR visit(IntrinsicExpression e) {
		switch (e.intrinsic) with (Intrinsic) {
			case Expect:
				return processExpr(e.args[0]);

			case PopCount, CountLeadingZeros, CountTrailingZeros:
				// TODO: Get a better estimate based on the argument's range.
				auto t = getBuiltin(e.type);
				return VR(0, t.getBits());

			default:
				return getRange(e.type);
		}
	}
}

unittest {
	import std.meta;
	foreach (T; AliasSeq!(uint, ulong)) {
		auto vrp = ValueRangePropagator!T();

		alias VR = ValueRange!T;
		VR v;

		enum LS = T.sizeof == long.sizeof;

		/**
		 * Test internal facilities
		 */
		assert(vrp.getRange(BuiltinType.Bool) == VR(0, 1));

		assert(vrp.getRange(BuiltinType.Byte) == VR(byte.min, byte.max));
		assert(vrp.getRange(BuiltinType.Ubyte) == VR(ubyte.min, ubyte.max));
		assert(vrp.getRange(BuiltinType.Short) == VR(short.min, short.max));
		assert(vrp.getRange(BuiltinType.Ushort) == VR(ushort.min, ushort.max));
		assert(vrp.getRange(BuiltinType.Int) == VR(int.min, int.max));
		assert(vrp.getRange(BuiltinType.Uint) == VR(uint.min, uint.max));

		static if (LS) {
			assert(vrp.getRange(BuiltinType.Long) == VR(long.min, long.max));
			assert(vrp.getRange(BuiltinType.Ulong) == VR(ulong.min, ulong.max));
		}

		assert(vrp.getRange(BuiltinType.Char) == VR(ubyte.min, ubyte.max));
		assert(vrp.getRange(BuiltinType.Wchar) == VR(ushort.min, ushort.max));
		assert(vrp.getRange(BuiltinType.Dchar) == VR(uint.min, uint.max));

		/**
		 * Constant we can reuse for variosu tests.
		 */
		import source.location;
		auto zero = new IntegerLiteral(Location.init, 0, BuiltinType.Int);
		auto i1 = new IntegerLiteral(Location.init, -7, BuiltinType.Int);
		auto i2 = new IntegerLiteral(Location.init, 42, BuiltinType.Int);
		auto i3 = new IntegerLiteral(Location.init, 2, BuiltinType.Uint);

		auto bmax = new IntegerLiteral(Location.init, 255, BuiltinType.Byte);

		auto ctrue = new BooleanLiteral(Location.init, true);
		auto cfalse = new BooleanLiteral(Location.init, false);

		auto tbool = Type.get(BuiltinType.Bool);

		auto tbyte = Type.get(BuiltinType.Byte);
		auto tubyte = Type.get(BuiltinType.Ubyte);

		auto tshort = Type.get(BuiltinType.Short);
		auto tushort = Type.get(BuiltinType.Ushort);

		auto tint = Type.get(BuiltinType.Int);
		auto tuint = Type.get(BuiltinType.Uint);

		auto tlong = Type.get(BuiltinType.Long);
		auto tulong = Type.get(BuiltinType.Ulong);

		/**
		 * Literals
		 */
		v = vrp.visit(cfalse);
		assert(v == VR(0));

		v = vrp.visit(ctrue);
		assert(v == VR(1));

		v = vrp.visit(zero);
		assert(v == VR(0));

		v = vrp.visit(i1);
		assert(v == VR(-7));

		v = vrp.visit(i2);
		assert(v == VR(42));

		v = vrp.visit(i3);
		assert(v == VR(2));

		/**
		 * Binary ops
		 */
		v = vrp.visit(
			new BinaryExpression(Location.init, tint, BinaryOp.Comma, i1, i2));
		assert(v == VR(42));

		// Technically, this is illegal, but it is out of scope of VRP to detect this, so will do.
		v = vrp.visit(
			new BinaryExpression(Location.init, tint, BinaryOp.Assign, i1, i2));
		assert(v == VR(42));

		v = vrp.visit(
			new BinaryExpression(Location.init, tint, BinaryOp.Add, i1, i2));
		assert(v == VR(35));

		v = vrp.visit(
			new BinaryExpression(Location.init, tint, BinaryOp.Sub, i1, i2));
		assert(v == VR(-49));

		v = vrp.visit(
			new BinaryExpression(Location.init, tint, BinaryOp.Mul, i1, i2));
		assert(v == VR(-294));

		v = vrp.visit(
			new BinaryExpression(Location.init, tuint, BinaryOp.UDiv, i1, i2));
		assert(v == VR((T.max - 6) / 42));

		v = vrp.visit(
			new BinaryExpression(Location.init, tint, BinaryOp.SDiv, i2, i1));
		assert(v == VR(-6));

		v = vrp.visit(
			new BinaryExpression(Location.init, tuint, BinaryOp.URem, i1, i2));
		assert(v == VR(LS ? 9 : 39));

		v = vrp.visit(
			new BinaryExpression(Location.init, tint, BinaryOp.SRem, i1, i3));
		assert(v == VR(-1));

		v = vrp.visit(
			new BinaryExpression(Location.init, tint, BinaryOp.Or, i1, i2));
		assert(v == VR(-5));

		v = vrp.visit(
			new BinaryExpression(Location.init, tint, BinaryOp.And, i1, i2));
		assert(v == VR(40));

		v = vrp.visit(
			new BinaryExpression(Location.init, tint, BinaryOp.Xor, i1, i2));
		assert(v == VR(-45));

		v = vrp.visit(new BinaryExpression(Location.init, tint,
		                                   BinaryOp.LeftShift, i1, i3));
		assert(v == VR(-28));

		v = vrp.visit(
			new BinaryExpression(Location.init, tuint,
			                     BinaryOp.UnsignedRightShift, i1, i3));
		assert(v == VR((T.max >> 2) - 1));

		v = vrp.visit(new BinaryExpression(Location.init, tint,
		                                   BinaryOp.SignedRightShift, i1, i3));
		assert(v == VR(-2));

		/**
		 * Unary ops
		 */
		v = vrp
			.visit(new UnaryExpression(Location.init, tuint, UnaryOp.Plus, i1));
		assert(v == VR(-7));

		v = vrp.visit(
			new UnaryExpression(Location.init, tuint, UnaryOp.Minus, i1));
		assert(v == VR(7));

		/**
		 * Variables
		 */
		import source.name;
		auto var =
			new Variable(Location.init, tuint.getParamType(ParamKind.Regular),
			             BuiltinName!"", i1);
		var.step = Step.Processed;

		v = vrp.visit(var);
		assert(v == VR(uint.min, uint.max));

		var.type = tbool;
		v = vrp.visit(var);
		assert(v == VR(0, 1));

		var.type = Type.get(BuiltinType.Short);
		v = vrp.visit(var);
		assert(v == VR(short.min, short.max));

		var.storage = Storage.Enum;
		v = vrp.visit(var);
		assert(v == VR(-7));

		var.storage = Storage.Static;
		v = vrp.visit(var);
		assert(v == VR(short.min, short.max));

		var.type = var.type.qualify(TypeQualifier.Immutable);
		v = vrp.visit(var);
		assert(v == VR(-7));

		/**
		 * Casts
		 */
		v = vrp.visit(
			new CastExpression(Location.init, CastKind.IntToBool, tbool, zero));
		assert(v == VR(0));

		v = vrp.visit(
			new CastExpression(Location.init, CastKind.IntToBool, tbool, i1));
		assert(v == VR(1));

		// FIXME: test the 0, 1 int to bool case ?

		v = vrp.visit(
			new CastExpression(Location.init, CastKind.Trunc, tubyte, i1));
		assert(v == VR(249));

		v = vrp.visit(
			new CastExpression(Location.init, CastKind.UPad, tint, bmax));
		assert(v == VR(255));

		v = vrp.visit(
			new CastExpression(Location.init, CastKind.SPad, tint, bmax));
		assert(v == VR(-1));

		v = vrp
			.visit(new CastExpression(Location.init, CastKind.Bit, tint, i1));
		assert(v == VR(-7));

		v = vrp
			.visit(new CastExpression(Location.init, CastKind.Qual, tint, i1));
		assert(v == VR(-7));

		v = vrp
			.visit(new CastExpression(Location.init, CastKind.Exact, tint, i1));
		assert(v == VR(-7));

		// Casts from floating point types to integer types

		auto dPi = new FloatLiteral(Location.init, 3.14, BuiltinType.Double);
		auto f0 = new FloatLiteral(Location.init, 0.0f, BuiltinType.Float);

		foreach (floatVal; [dPi, f0]) {
			foreach (t;
				[tshort, tushort, tint, tuint, tlong, tulong, tbyte, tubyte]
			) {
				const bt = t.builtin();
				if (bt.getSize() <= T.sizeof) {
					const CastKind ck = isSigned(bt)
						? CastKind.FloatToSigned
						: CastKind.FloatToUnsigned;
					auto castExpr =
						new CastExpression(Location.init, ck, t, floatVal);
					const vr = vrp.visit(castExpr);
					// dmd doesn't try to do anything clever here,
					// i.e. assume the cast to T could yield any T.
					assert(vr == vrp.getRange(t));
				}
			}
		}

		/**
		 * Intrinsics.
		 */
		v = vrp.visit(
			new IntrinsicExpression(Location.init, tbool, Intrinsic.Expect,
			                        [cfalse, cfalse]));
		assert(v == VR(0));

		v = vrp.visit(
			new IntrinsicExpression(Location.init, tbool, Intrinsic.Expect,
			                        [cfalse, ctrue]));
		assert(v == VR(0));

		v = vrp.visit(
			new IntrinsicExpression(Location.init, tbool, Intrinsic.Expect,
			                        [ctrue, ctrue]));
		assert(v == VR(1));

		foreach (t;
			[tshort, tushort, tint, tuint, tlong, tulong, tbyte, tubyte]
		) {
			const bt = t.builtin();
			auto expected = VR(0, bt.getBits());

			v = vrp.visit(new IntrinsicExpression(Location.init, t,
			                                      Intrinsic.PopCount, [i2]));
			assert(v == expected);

			v = vrp.visit(
				new IntrinsicExpression(Location.init, t,
				                        Intrinsic.CountLeadingZeros, [i2]));
			assert(v == expected);

			v = vrp.visit(
				new IntrinsicExpression(Location.init, t,
				                        Intrinsic.CountTrailingZeros, [i2]));
			assert(v == expected);
		}
	}
}

private:

auto isValidExpr(Expression e) {
	auto t = e.type.getCanonicalAndPeelEnum();
	return t.kind == TypeKind.Builtin && canConvertToIntegral(t.builtin);
}

bool isMask(T)(T mask) if (isIntegral!T) {
	auto p = mask + 1;
	return (p & -p) == p;
}

unittest {
	assert(isMask(0));
	assert(isMask(1));
	assert(!isMask(2));
	assert(isMask(3));
	assert(!isMask(10));
	assert(isMask(255));
}

struct ValueRange(T) if (is(uint : T) && isIntegral!T) {
	T min = T.min;
	T max = T.max;

	this(T min, T max) {
		this.min = min;
		this.max = max;
	}

	this(T val) {
		this(val, val);
	}

	alias U = Unsigned!T;
	alias S = Signed!T;

	alias URange = ValueRange!U;
	alias SRange = ValueRange!S;

	enum Bits = T.sizeof * 8;

	@property
	U range() const {
		return max - min;
	}

	@property
	bool full() const {
		return range == typeof(range).max;
	}

	@property
	auto unsigned() const {
		return URange(min, max);
	}

	@property
	auto signed() const {
		return SRange(min, max);
	}

	@property
	auto normalized() const out(result) {
		assert(result.range >= range);
		assert(result.min <= result.max);
	} do {
		// This is lossy, only use when stritcly necessary.
		if (min > max) {
			return ValueRange();
		}

		return this;
	}

	@property
	bool containsZero() const {
		return unsigned.normalized.min == 0;
	}

	@property
	bool isReduced() const {
		// A reduced range if of the form XXXX0000 => XXXX1111.
		auto x = (min ^ max) + 1;
		return (x & -x) == x;
	}

	auto negate(bool negate = true) const {
		auto negMask = -T(negate);
		auto posMask = T(negate) - 1;

		return ValueRange((min & posMask) | (-max & negMask),
		                  (max & posMask) | (-min & negMask));
	}

	auto unionWith(ValueRange other) const {
		auto twraparound = this.max < this.min;
		auto owraparound = other.max < other.min;

		if (twraparound == owraparound) {
			import std.algorithm : min, max;
			auto rmin = min(this.min, other.min);
			auto rmax = max(this.max, other.max);

			auto r = ValueRange(rmin, rmax);

			if (twraparound) {
				// Checks if we don't do more than a full range
				if (rmin <= rmax) {
					return ValueRange();
				}
			} else {
				// Maybe a wraparound range would be tighter.
				auto wmin = max(this.min, other.min);
				auto wmax = min(this.max, other.max);

				auto w = ValueRange(wmin, wmax);

				// If so, wraparound !
				if (wmin > wmax && (w.range < r.range)) {
					return w;
				}
			}

			return r;
		}

		ValueRange wr = this;
		if (owraparound) {
			import std.algorithm : swap;
			swap(wr, other);
		}

		// Try to merge up and down, and chose the tighter.
		import std.algorithm : min, max;
		auto d = ValueRange(wr.min, max(wr.max, other.max));
		if (d.min <= d.max) {
			d = ValueRange();
		}

		auto u = ValueRange(min(wr.min, other.min), wr.max);
		if (u.min <= u.max) {
			u = ValueRange();
		}

		return u.range < d.range ? u : d;
	}

	@property
	ValueRange!A as(A)() const if (is(uint : A) && isIntegral!A)
			out(result; result.range <= Unsigned!A.max) {
		static if (T.sizeof <= A.sizeof) {
			// Type are the same size, it is a noop.
			return ValueRange!A(min, max);
		} else {
			enum MaxRange = Unsigned!A.max;

			// If the current range is larger than the destination: full range.
			if (range >= MaxRange) {
				return ValueRange!A();
			}

			// Now the range fits. It's now a matter
			// of wrapping things around the right way.

			// If we have a proper unsigned range, go for it.
			auto urange = this.unsigned;
			if (urange.min <= urange.max) {
				alias UA = Unsigned!A;
				auto umin = cast(UA) urange.min;
				auto umax = cast(UA) urange.max;

				// No overflow check because the high bits are lost anyway.
				return ValueRange!UA(umin, umax).as!A;
			}

			// If we have a proper signed range, go for it.
			auto srange = this.signed;
			if (srange.min <= srange.max) {
				alias SA = Unsigned!A;
				auto smin = cast(SA) srange.min;
				auto smax = cast(SA) srange.max;

				// No overflow check because the high bits are lost anyway.
				return ValueRange!SA(smin, smax).as!A;
			}

			// OK, we have some sort of screwed up range :)
			return ValueRange!A();
		}
	}

	/**
	 * Fit a range into a smaller type with less bits.
	 *
	 * Try to produce a wrappign around range when possible.
	 * This will create ranges needlessly large when normalizing,
	 * but it doesn't matter as well formed expression should
	 * UPad or SPad before normalizing due to integer promotion.
	 */
	ValueRange trunc(U mask) const
			out(result; result.range <= mask && isMask(mask)) {
		auto smask = mask >> 1;

		// Worse case scenario, we can return this.
		auto fail =
			isSigned!T ? ValueRange(~smask, smask) : ValueRange(0, mask);

		// We do something similar to as!T, except that we sign extend
		// manually in the signed range case.
		if (range > mask) {
			return fail;
		}

		auto urange = this.unsigned;
		if (urange.min <= urange.max) {
			auto umin = urange.min & mask;
			auto umax = urange.max & mask;

			// Maybe umax wrapped around, in which case we wrap around.
			if (umax < umin) {
				umin = umin | ~mask;
			}

			return ValueRange(umin, umax);
		}

		auto srange = this.signed;
		if (srange.min <= srange.max) {
			// Other cases are already handled as unsigned.
			assert(srange.min < 0);
			assert(srange.max >= 0);

			auto smin = srange.min | ~mask;
			auto smax = srange.max & mask;
			return ValueRange(smin, smax);
		}

		// I don't think this can actually happen unless mask is all ones.
		// In which case, why we are truncating is a mystery to begin with.
		assert(mask + 1 == 0);
		return fail;
	}

	/**
	 * Because it is a signed operation, padding is actually the one
	 * finishing the truncate work. It works because properly formed
	 * expressions are promoted before being used, and this promotion
	 * translates into a pad operation here.
	 */
	ValueRange pad()(U mask) const if (isUnsigned!T)
			out(result; result.range <= mask && isMask(mask)) {
		auto bits = min ^ max;
		return ((min > max) || (bits & ~mask))
			? ValueRange(0, mask)
			: ValueRange(min & mask, max & mask);
	}

	ValueRange pad()(U mask) const if (isSigned!T)
			out(result; result.range <= mask && isMask(mask)) {
		auto offset = URange(~(mask >> 1));
		return ((unsigned - offset).pad(mask) + offset).signed;
	}

	bool opEquals(ValueRange rhs) const {
		return (full && rhs.full) || (min == rhs.min && max == rhs.max);
	}

	auto opUnary(string op : "-")() const {
		return ValueRange(-max, -min);
	}

	auto opUnary(string op : "~")() const {
		return ValueRange(~max, ~min);
	}

	auto opBinary(string op : "+")(ValueRange rhs) const {
		ulong lrange = this.range;
		ulong rrange = rhs.range;
		auto range = lrange + rrange;

		// If the type is small enough, do the easy dance.
		auto overflow =
			Bits < 64 ? range > U.max : range < lrange && range < rrange;

		return overflow
			? ValueRange()
			: ValueRange(min + rhs.min, max + rhs.max);
	}

	auto opBinary(string op : "-")(ValueRange rhs) const {
		return this + -rhs;
	}

	auto smul()(ValueRange rhs) const if (isUnsigned!T)
			in(min > max && max != 0) {
		auto v0 = ValueRange(0, max) * rhs;
		auto v1 = ValueRange(0, -min) * -rhs;

		if (rhs.min <= rhs.max) {
			// If rhs don't wrap around, 0 should one of v0 bound.
			assert(v0.min == 0 || v0.max == 0);
			auto rmin = v0.min ? v0.min : v1.min;
			auto rmax = v0.min ? v1.max : v0.max;
			if (rmin > rmax) {
				return ValueRange(rmin, rmax);
			}
		} else {
			// If rhs wrap around, v1 and v0 will wrap around or be 0.
			import std.algorithm : min, max;
			auto rmin = min(v0.min, v1.min);
			auto rmax = max(v0.max, v1.max);
			if (rmin > rmax) {
				return ValueRange(rmin, rmax);
			}
		}

		// We have an overflow.
		return ValueRange();
	}

	auto umul()(ValueRange rhs) const if (isUnsigned!T)
			in(min <= max && rhs.min <= rhs.max) {
		// So we can swap modify.
		ValueRange lhs = this;

		// If the whole range is in the negative, a * b = -(a * b).
		auto lneg = lhs.min > S.max;
		lhs = lhs.negate(lneg);

		auto rneg = rhs.min > S.max;
		rhs = rhs.negate(rneg);

		// Zero is a special case as it always produce a
		// range containign only itself. By splitting it,
		// we can make sure we minimally extend the range
		// to include 0 at the end.
		bool hasZero;

		if (lhs.min == 0) {
			hasZero = true;
			lhs.min = 1;
		}

		if (rhs.min == 0) {
			hasZero = true;
			rhs.min = 1;
		}

		// Alright, now we are in a canonical form, we can proceed.
		static T mulhi(ulong a, ulong b) {
			static if (Bits < 64) {
				// XXX: VRP can't figure that one out aparently.
				return cast(T) ((a * b) >> Bits);
			} else {
				import util.math : mulhi;
				return mulhi(a, b);
			}
		}

		// If this overflows, then return a full range.
		if (mulhi(lhs.min, rhs.min) != mulhi(lhs.max, rhs.max)) {
			return ValueRange();
		}

		auto res = ValueRange(lhs.min * rhs.min, lhs.max * rhs.max)
			.negate(lneg != rneg);

		// We try to zero extend the range to be the most restrictive.
		if (!hasZero) {
			return res;
		}

		if (res.min <= -res.max) {
			return ValueRange(0, res.max);
		} else {
			return ValueRange(res.min, 0);
		}
	}

	auto opBinary(string op : "*")(ValueRange rhs) const if (isSigned!T) {
		// Multiplication doesn't care about sign.
		return (this.unsigned * rhs.unsigned).signed;
	}

	ValueRange opBinary(string op : "*")(ValueRange rhs) const
			if (isUnsigned!T) {
		// Multiplication by 0 is always 0.
		auto zero = ValueRange(0);
		if (this == zero || rhs == zero) {
			// Zero is pain in the ass as it reduce ranges
			// to one element, making it hard to figure out
			// if an overflow occured.
			return zero;
		}

		// Try to avoid slicing when not necessary.
		if (max == 0) {
			// [-a, 0] * rhs = -(rhs * [0 .. a])
			return -(rhs * -this);
		}

		if (rhs.max == 0) {
			return -(this * -rhs);
		}

		// If the range is of the kind [min .. T.max][0 .. max]
		// we split it in half and union the result.
		if (min > max) {
			return smul(rhs);
		}

		if (rhs.min > rhs.max) {
			return rhs.smul(this);
		}

		return umul(rhs);
	}

	auto opBinary(string op : "/")(ValueRange rhs) const {
		rhs = rhs.normalized;
		if (rhs == ValueRange(0)) {
			// We have a division by 0, bail out.
			return ValueRange();
		}

		// Remove 0 from rhs.
		rhs.min = rhs.min ? rhs.min : 1;
		rhs.max = rhs.max ? rhs.max : U.max;

		// Make sure we normalize full ranges.
		ValueRange lhs = this.normalized;
		if (isUnsigned!T) {
			return ValueRange(lhs.min / rhs.max, lhs.max / rhs.min);
		} else {
			if (rhs.containsZero) {
				import std.algorithm : min, max;
				return
					ValueRange(min(lhs.min, -lhs.max), max(lhs.max, -lhs.min));
			}

			// Alright, this is a signed division.
			bool neg = rhs.max < 0;

			// a / -b = -(a / b)
			rhs = rhs.negate(neg);

			auto min = lhs.min / (lhs.min < 0 ? rhs.min : rhs.max);
			auto max = lhs.max / (lhs.max < 0 ? rhs.max : rhs.min);
			return ValueRange(min, max).negate(neg);
		}
	}

	auto srem()(ValueRange rhs) const if (isSigned!T)
			in(this != ValueRange(0) && rhs is rhs.normalized) {
		// a % -b = a % b
		rhs = rhs.negate(rhs.max < 0);

		if (rhs.containsZero) {
			import std.algorithm : max;
			rhs = ValueRange(1, max(-rhs.min, rhs.max));
		}

		auto lhs = this.normalized;

		// lhs is positive or negative.
		auto lneg = lhs.max <= 0;
		if (lneg || lhs.min >= 0) {
			return lhs.negate(lneg).unsigned.urem(rhs.unsigned).signed
			          .negate(lneg);
		}

		// Ok lhs can be both positive and negative.
		// Compute both range and aggregate.
		auto pos = URange(0, lhs.max).urem(rhs.unsigned);
		auto neg = URange(0, -lhs.min).urem(rhs.unsigned);

		return ValueRange(-neg.max, pos.max);
	}

	auto urem()(ValueRange rhs) const if (isUnsigned!T) in {
		assert(this != ValueRange(0));
		assert(rhs is rhs.normalized);
		assert(rhs.min > 0);
	} do {
		auto lhs = this.normalized;

		// If lhs is within the bound of rhs.
		if (lhs.max < rhs.max) {
			// If rhs.min <= rhs.max we need to 0 extend.
			return ValueRange((lhs.max > rhs.min) ? 0 : lhs.min, lhs.max);
		}

		// We count how many time we can remove rhs.max from lhs.
		auto lminrmaxloop = lhs.min / rhs.max;
		auto lmaxrmaxloop = lhs.max / rhs.max;

		// If these counts aren't the same, we have the full modulo range.
		if (lminrmaxloop != lmaxrmaxloop) {
			return ValueRange(0, rhs.max - 1);
		}

		// Same process for rhs.min.
		auto lminrminloop = lhs.min / rhs.min;
		auto lmaxrminloop = lhs.max / rhs.min;

		// FIXME: Idealy, we would look for the biggest
		// value in rhs that have the correct count.
		if (lminrminloop != lmaxrminloop || lminrminloop != lminrmaxloop) {
			return ValueRange(0, rhs.max - 1);
		}

		// At this point, we know that as rhs grow, the result will reduce.
		// and as lhs grow, the result will increase.
		return ValueRange(lhs.min % rhs.max, lhs.max % rhs.min);
	}

	auto opBinary(string op : "%")(ValueRange rhs) const {
		rhs = rhs.normalized;
		if (rhs == ValueRange(0)) {
			// We have a division by 0, bail out.
			return this;
		}

		static if (isSigned!T) {
			return srem(rhs);
		} else {
			rhs.min = rhs.min ? rhs.min : 1;
			return urem(rhs);
		}
	}

	auto sshl()(ValueRange rhs) const if (isUnsigned!T)
			in(rhs is rhs.normalized && rhs.max < Bits) {
		auto v0 = ValueRange(0, max).ushl(rhs);
		auto v1 = -ValueRange(0, -min).ushl(rhs);

		if (v0.max >= v1.min) {
			return ValueRange();
		}

		return ValueRange(v1.min, v0.max);
	}

	auto ushl()(ValueRange rhs) const if (isUnsigned!T) in {
		assert(rhs is rhs.normalized);
		assert(rhs.max < Bits);
		assert(this.min <= Signed!T.max);
	} do {
		auto minhi = rhs.min ? (min >> (Bits - rhs.min)) : 0;
		auto maxhi = rhs.max ? (max >> (Bits - rhs.max)) : 0;
		if (minhi != maxhi) {
			return ValueRange();
		}

		return ValueRange(min << rhs.min, max << rhs.max);
	}

	auto opBinary(string op : "<<")(ValueRange rhs) const if (isSigned!T) {
		return (this.unsigned << rhs.unsigned).signed;
	}

	auto opBinary(string op : "<<")(ValueRange rhs) const if (isUnsigned!T) {
		rhs = rhs.normalized;

		// We are in undefined territory, pessimize.
		if (rhs.max >= Bits) {
			// We assume that shifting 0 is alright.
			return this == ValueRange(0) ? ValueRange(0) : ValueRange();
		}

		if (min > max) {
			return sshl(rhs);
		}

		ValueRange lhs = this;

		auto lneg = min > S.max;
		lhs = lhs.negate(lneg);

		auto res = lhs.ushl(rhs);
		return res.negate(lneg);
	}

	auto sshr(URange rhs) const in(rhs is rhs.normalized && rhs.min < Bits) {
		auto v0 = ValueRange(0, max).ushr(rhs);
		auto v1 = ValueRange(min, U.max).ushr(rhs);

		auto res = ValueRange();

		U rmax = v0.max;
		U rmin = v1.min;
		if (rmin > rmax) {
			res = ValueRange(rmin, rmax);
		}

		if (isUnsigned!T) {
			rmax = U.max >> rhs.min;
			if (res.range > rmax) {
				// If 0 .. umax >> rhs.min is smaller than
				// what we have now, use that instead.
				res = ValueRange(0, rmax);
			}
		}

		return res;
	}

	auto ushr(URange rhs) const in(rhs is rhs.normalized && rhs.min < Bits) {
		T rmin = min >> (min < 0 ? rhs.min : rhs.max);
		if (min >= 0 && rhs.max >= Bits) {
			rmin = 0;
		}

		T rmax = max >> (max < 0 ? rhs.max : rhs.min);
		if (max < 0 && rhs.max >= Bits) {
			rmax = Unsigned!T.max;
		}

		return ValueRange(rmin, rmax);
	}

	auto opBinary(string op : ">>")(ValueRange other) const {
		auto rhs = other.unsigned.normalized;

		// We are in undefined territory, pessimize.
		if (rhs.min >= Bits) {
			// We assume that shifting 0 is alright.
			// XXX: This is undefined, so I'm not sure what to do.
			// Probably anything is fine as it is undefined :)
			return ValueRange(0);
		}

		auto lhs = this.unsigned;
		return lhs.min > lhs.max ? sshr(rhs) : ushr(rhs);
	}

	auto opBinary(string op : ">>>")(ValueRange rhs) const if (isSigned!T) {
		return (this.unsigned >>> rhs.unsigned).signed;
	}

	auto opBinary(string op : ">>>")(ValueRange rhs) const if (isUnsigned!T) {
		return this >> rhs;
	}

	/**
	 * This whole dance is O(n^2) but n is small, so it doesn't matter.
	 * This split lhs into reduced ranges and combine the results.
	 */
	ValueRange reduceOrdered(alias doOp, bool hasFlipped = false)(
		ValueRange rhs,
	) const if (isUnsigned!T) in(min <= max && rhs.min <= rhs.max) {
		static nextRange(T t) out(result) {
			assert((t & result) == 0);
		} do {
			return (t & -t) - 1;
		}

		ValueRange lhs = this;

		// Just pick one value we know is in the range.
		auto result = doOp(ValueRange(lhs.min), ValueRange(rhs.min));

		while (true) {
			T split;
			ValueRange reduced;

			auto lminrange = nextRange(lhs.min);
			auto lmaxrange = nextRange(lhs.max + 1);

			auto reduceFromMin = lminrange <= lmaxrange;
			if (reduceFromMin) {
				split = lhs.min | lminrange;
				reduced = ValueRange(lhs.min, split);
			} else {
				split = lhs.max - lmaxrange;
				reduced = ValueRange(split, lhs.max);
			}

			static if (hasFlipped) {
				assert(reduced.isReduced && rhs.isReduced);
				result = result.unionWith(doOp(reduced, rhs));
			} else {
				assert(reduced.isReduced);
				result =
					result.unionWith(rhs.reduceOrdered!(doOp, true)(reduced));
			}

			// We just fully reduced this range, return.
			if (reduced == lhs) {
				return result;
			}

			lhs = reduceFromMin
				? ValueRange(split + 1, lhs.max)
				: ValueRange(lhs.min, split - 1);
		}
	}

	ValueRange reduce(
		alias doOp,
		bool hasFlipped = false,
	)(ValueRange rhs) const if (isUnsigned!T) {
		if (min <= max) {
			return hasFlipped
				? reduceOrdered!doOp(rhs)
				: rhs.reduce!(doOp, true)(this);
		}

		return rhs.reduce!(doOp, true)(ValueRange(0, max))
		          .unionWith(rhs.reduce!(doOp, true)(ValueRange(min, T.max)));
	}

	auto opBinary(string op : "&")(ValueRange rhs) const if (isSigned!T) {
		return (this.unsigned & rhs.unsigned).signed;
	}

	ValueRange opBinary(string op : "&")(ValueRange rhs) const
			if (isUnsigned!T) {
		static doAnd(ValueRange lhs, ValueRange rhs) {
			return ValueRange(lhs.min & rhs.min, lhs.max & rhs.max);
		}

		return reduce!doAnd(rhs);
	}

	auto opBinary(string op : "|")(ValueRange rhs) const {
		// Just bitflip, and use the and logic.
		return ~(~this & ~rhs);
	}

	auto opBinary(string op : "^")(ValueRange rhs) const if (isSigned!T) {
		return (this.unsigned ^ rhs.unsigned).signed;
	}

	auto opBinary(string op : "^")(ValueRange rhs) const if (isUnsigned!T) {
		static doXor(ValueRange lhs, ValueRange rhs) {
			auto mask = (lhs.min ^ lhs.max) | (rhs.min ^ rhs.max);
			auto base = lhs.min ^ rhs.min;
			return ValueRange(base & ~mask, base | mask);
		}

		return reduce!doXor(rhs);
	}
}

unittest {
	template coerceRange(T) {
		auto coerceRange(A...)(A args) {
			alias U = CommonType!(A, T);
			return ValueRange!U(args).as!T;
		}
	}

	void testComplement(T)(ValueRange!T a, ValueRange!T b) {
		assert(~a == b, "~a = b");
		assert(a == ~b, "a = ~b");

		auto one = ValueRange!T(1);
		assert(-a == b + one, "-a = b + 1");
		assert(a == -b - one, "a = -b - 1");
	}

	void testUnion(T)(ValueRange!T a, ValueRange!T b, ValueRange!T c) {
		assert(a.unionWith(b) == c, "a U b = c");
		assert(b.unionWith(a) == c, "b U a = c");

		assert((-a).unionWith(-b) == -c, "-a U -b = -c");
		assert((-b).unionWith(-a) == -c, "-b U -a = -c");
	}

	void testAddSub(T)(ValueRange!T a, ValueRange!T b, ValueRange!T c,
	                   ValueRange!T d) {
		// Add
		assert(a + b == c, "a + b = c");
		assert(b + a == c, "b + a = c");
		assert(-a - b == -c, "-a - b = -c");
		assert(-(a + b) == -c, "-(a + b) = -c");
		assert(-a + -b == -c, "-a + -b = -c");

		// Sub
		assert(a - b == d, "a - b = d");
		assert(b - a == -d, "b - a = -d");
		assert(a + -b == d, "a + -b = d");
		assert(-a - -b == -d, "-a - -b = -d");
	}

	void testMul(T)(ValueRange!T a, ValueRange!T b, ValueRange!T c) {
		assert(a * b == c, "a * b = c");
		assert(b * a == c, "b * a = c");

		bool asym = a == -a;
		bool bsym = b == -b;

		assert(-a * b == (asym ? c : -c), "-a * b = -c");
		assert(b * -a == (asym ? c : -c), "b * -a = -c");
		assert(a * -b == (bsym ? c : -c), "a * -b = -c");
		assert(-b * a == (bsym ? c : -c), "-b * a = -c");
		assert(-a * -b == ((asym == bsym) ? c : -c), "-a * -b = c");
		assert(-b * -a == ((asym == bsym) ? c : -c), "-b * -a = c");
	}

	void testDiv(T)(ValueRange!T a, ValueRange!T b, ValueRange!T c) {
		assert(a / b == c, "a / b = c");

		static if (isSigned!T) {
			assert(-a / b == -c, "-a / b = -c");
			assert(a / -b == -c, "a / -b = -c");
			assert(-a / -b == c, "-a / -b = c");
		}
	}

	void testRem(T)(ValueRange!T a, ValueRange!T b, ValueRange!T c) {
		assert(a % b == c, "a % b = c");

		static if (isSigned!T) {
			assert(-a % b == -c, "-a % b = -c");
			assert(a % -b == c, "a % -b = c");
			assert(-a % -b == -c, "-a % -b = -c");
		}
	}

	void testLShift(T)(ValueRange!T a, ValueRange!T b, ValueRange!T c) {
		assert(a << b == c, "a << b = c");
	}

	void testSRShift(T)(ValueRange!T a, ValueRange!T b, ValueRange!T c) {
		assert(a >> b == c, "a >> b = c");
	}

	void testURShift(T)(ValueRange!T a, ValueRange!T b, ValueRange!T c) {
		assert(a >>> b == c, "a >>> b = c");
	}

	void testAnd(T)(ValueRange!T a, ValueRange!T b, ValueRange!T c) {
		assert((a & b) == c, "a & b = c");
		assert((b & a) == c, "b & a = c");
	}

	void testOr(T)(ValueRange!T a, ValueRange!T b, ValueRange!T c) {
		assert((a | b) == c, "a | b = c");
		assert((b | a) == c, "b | a = c");
	}

	void testXor(T)(ValueRange!T a, ValueRange!T b, ValueRange!T c) {
		assert((a ^ b) == c, "a ^ b = c");
		assert((b ^ a) == c, "b ^ a = c");
	}

	import std.meta;
	foreach (T; AliasSeq!(int, uint, long, ulong)) {
		alias VR = coerceRange!T;
		enum LS = T.sizeof == long.sizeof;

		// Some useful values
		auto umax = Unsigned!T.max;
		auto umin = Unsigned!T.min;
		auto smax = umax >>> 1;
		auto smin = smax + 1;

		/**
		 * Test coercion
		 */
		assert(VR() == ValueRange!T());
		assert(VR(0) == ValueRange!T(0));
		assert(VR(1, 25) == ValueRange!T(1, 25));
		assert(VR(-3, 12) == ValueRange!T(-3, 12));
		assert(VR(-44, -26) == ValueRange!T(-44, -26));

		// Check coercion with wrap around
		assert(ValueRange!int(25, 1).as!T == VR(25, 1));
		assert(ValueRange!long(25, 1).as!T == (LS ? VR(25, 1) : VR()));
		assert(ValueRange!int(-25, -37).as!T == VR(-25, -37));
		assert(ValueRange!long(-25, -37).as!T == (LS ? VR(-25, -37) : VR()));

		/**
		 * Test normalization
		 */
		assert(VR().normalized == VR());
		assert(VR(15).normalized == VR(15));
		assert(VR(3, 15).normalized == VR(3, 15));
		assert(VR(-38, -15).normalized == VR(-38, -15));

		// Wraparound
		assert(VR(-31, 11).normalized == (isSigned!T ? VR(-31, 11) : VR()));
		assert(VR(31, smax + 31).normalized
			== (isSigned!T ? VR() : VR(31, smax + 31)));

		// Degenerate ranges
		assert(VR(138, 15).normalized == VR());
		assert(VR(-38, -153).normalized == VR());

		/**
		 * Test truncation
		 */
		assert(VR(0).trunc(0xFF) == VR(0));
		assert(VR(15).trunc(0xFF) == VR(15));
		assert(VR(-8, 15).trunc(0xFF) == VR(-8, 15));
		assert(VR(-80, -8).trunc(0xFF) == VR(176, 248));

		// Do not fit
		assert(VR(5, 300).trunc(0xFF)
			== (isSigned!T ? VR(-0x80, 0x7F) : VR(0, 0xFF)));
		assert(
			VR().trunc(0xFF) == (isSigned!T ? VR(-0x80, 0x7F) : VR(0, 0xFF)));

		// Fit via wraparound
		assert(VR(250, 260).trunc(0xFF) == VR(-6, 4));

		/**
		 * Test padding
		 */
		assert(VR(0).pad(0xFF) == VR(0));
		assert(VR(15).pad(0xFF) == VR(15));
		assert(VR(255).pad(0xFF) == (isSigned!T ? VR(-1) : VR(255)));
		assert(
			VR(176, 248).pad(0xFF) == (isSigned!T ? VR(-80, -8) : VR(176, 248))
		);
		assert(
			VR(-80, -8).pad(0xFF) == (isSigned!T ? VR(-80, -8) : VR(176, 248)));

		// Immaterializable ranges
		assert(
			VR(1, 158).pad(0xFF) == (isSigned!T ? VR(-128, 127) : VR(1, 158)));
		assert(VR(-8, 15).pad(0xFF) == (isSigned!T ? VR(-8, 15) : VR(0, 255)));
		assert(
			VR(5, 300).pad(0xFF) == (isSigned!T ? VR(-0x80, 0x7F) : VR(0, 0xFF))
		);

		/**
		 * Test complement
		 */
		testComplement(VR(0), VR(-1));
		testComplement(VR(1), VR(-2));
		testComplement(VR(42), VR(-43));

		// T.min and T.max are a special cases
		testComplement(VR(T.min), VR(T.max));

		// Full range
		testComplement(VR(), VR());

		// Various ranges
		testComplement(VR(0, 42), VR(-43, -1));
		testComplement(VR(42, 0), VR(-1, -43));
		testComplement(VR(23, 38), VR(-39, -24));
		testComplement(VR(-23, 38), VR(-39, 22));

		/**
		 * Test union
		 */
		testUnion(VR(), VR(), VR());
		testUnion(VR(0), VR(0), VR(0));
		testUnion(VR(42), VR(42), VR(42));
		testUnion(VR(1), VR(7), VR(1, 7));

		// Positive ranges
		testUnion(VR(1, 7), VR(17, 23), VR(1, 23)); // disjoint
		testUnion(VR(3, 23), VR(17, 27), VR(3, 27)); // overlaping
		testUnion(VR(3, 27), VR(17, 23), VR(3, 27)); // contained

		// Negative ranges
		testUnion(VR(-7, -1), VR(-23, -17), VR(-23, -1)); // disjoint
		testUnion(VR(-17, -3), VR(-23, -13), VR(-23, -3)); // overlaping
		testUnion(VR(-27, -3), VR(-23, -17), VR(-27, -3)); // contained

		// Signed ranges
		testUnion(VR(-7, 1), VR(3, 12), VR(-7, 12)); // disjoint
		testUnion(VR(-7, 7), VR(3, 12), VR(-7, 12)); // overlaping
		testUnion(VR(-7, 12), VR(3, 5), VR(-7, 12)); // contained

		testUnion(VR(-7, -1), VR(3, 12), VR(-7, 12)); // disjoint
		testUnion(VR(-7, 7), VR(-3, 12), VR(-7, 12)); // overlaping
		testUnion(VR(-7, 12), VR(-3, 5), VR(-7, 12)); // contained

		// Degenerate ranges
		testUnion(VR(23, 1), VR(3, 12), VR(23, 12)); // disjoint
		testUnion(VR(23, 7), VR(3, 12), VR(23, 12)); // overlaping
		testUnion(VR(23, 12), VR(3, 5), VR(23, 12)); // contained

		/**
		 * Test add/sub
		 */
		testAddSub(VR(1), VR(-1), VR(0), VR(2));
		testAddSub(VR(-5, 0), VR(-1, 5), VR(-6, 5), VR(-10, 1));
		testAddSub(VR(5, 6), VR(-3, 5), VR(2, 11), VR(0, 9));
		testAddSub(VR(-12, 85), VR(5, 53), VR(-7, 138), VR(-65, 80));

		// Flirting with the limit
		testAddSub(VR(1, smax), VR(smin, -1), VR(smin + 1, smax - 1),
		           VR(2, -1));

		// overflow
		testAddSub(VR(0, -42), VR(42, -1), VR(), VR());
		testAddSub(VR(1, long.max + 2), VR(long.min, -1), VR(), VR());

		/**
		 * Test mul
		 */
		// Zero time all kind of things is always 0.
		testMul(VR(0), VR(), VR(0));
		testMul(VR(0), VR(0), VR(0));
		testMul(VR(0), VR(2, 3), VR(0));
		testMul(VR(0), VR(-7, 3), VR(0));
		testMul(VR(0), VR(3, -23), VR(0));
		testMul(VR(0), VR(-39, -23), VR(0));

		// One time all of things is all kind of things.
		testMul(VR(1), VR(), VR());
		testMul(VR(1), VR(2, 3), VR(2, 3));
		testMul(VR(1), VR(-7, 3), VR(-7, 3));
		testMul(VR(1), VR(3, -23), VR(3, -23));
		testMul(VR(1), VR(-39, -23), VR(-39, -23));

		// Full ranges
		testMul(VR(), VR(), VR());

		// [0 .. 1] do zero extend.
		testMul(VR(0, 1), VR(2, 3), VR(0, 3));
		testMul(VR(0, 1), VR(-7, 3), VR(-7, 3));
		testMul(VR(0, 1), VR(3, -23), VR(0, -23));
		testMul(VR(0, 1), VR(-39, -23), VR(-39, 0));

		// Symetric ranges are tools of the devil.
		testMul(VR(0, 1), VR(3, -3), VR(0, -3));
		testMul(VR(-1, 1), VR(3, 5), VR(-5, 5));

		// min < max
		testMul(VR(2, 3), VR(7, 23), VR(14, 69));
		testMul(VR(1), VR(125, -32), VR(125, -32));
		testMul(VR(-7, -4), VR(-5, -3), VR(12, 35));
		testMul(VR(3, 3037000500), VR(7, 3037000500),
		        VR(21, 9223372037000250000UL));

		// min > max on one side
		testMul(VR(-5, 42), VR(1), VR(-5, 42));
		testMul(VR(-5, 42), VR(2, 5), VR(-25, 210));
		testMul(VR(-5, 12), VR(0, 7), VR(-35, 84));
		testMul(VR(-5, 42), VR(0), VR(0));
		testMul(VR(5, 3037000500), VR(-12, 3037000500),
		        VR(-36444006000, 9223372037000250000UL));

		// min > max on both side
		testMul(VR(-1, 5), VR(-7, 22), VR(-35, 110));
		testMul(VR(-11, 3037000500), VR(-8, 3037000500),
		        VR(-33407005500, 9223372037000250000UL));

		// overflow
		testMul(VR(123), VR(long.min, ulong.max), VR());
		testMul(VR(0, 4294967296), VR(0, 4294967297), VR());
		testMul(VR(-23, 4294967296), VR(10, 4294967297), VR());
		testMul(VR(-3037000500, 3037000500), VR(-3037000500, 3037000500), VR());

		/**
		 * Test div
		 */
		// unsigned numerator.
		testDiv(VR(23), VR(5), VR(4));
		testDiv(VR(23, 125), VR(5, 7), VR(3, 25));
		testDiv(VR(0, 201), VR(12, 17), VR(0, 16));

		// signed numerator
		testDiv(VR(-23), VR(5), isSigned!T ? VR(-4) : VR((T.min - 23) / 5));
		testDiv(VR(-27, 31), VR(5, 9),
		        isSigned!T ? VR(-5, 6) : VR(0, T.max / 5));
		testDiv(VR(-23, 125), VR(89351496, 458963274),
		        isSigned!T ? VR(0) : VR(0, (T.min - 23) / 89351496));

		// signed denumerator
		testDiv(VR(23), VR(-5), isSigned!T ? VR(-4) : VR(0));
		testDiv(VR(23, 125), VR(-7, -5), isSigned!T ? VR(-25, -3) : VR(0));

		// division by 0.
		testDiv(VR(42), VR(0), VR());
		testDiv(VR(42), VR(0, 25), VR(1, 42));
		testDiv(VR(42), VR(-8, 0), isSigned!T ? VR(-42, -5) : VR(0, 42));
		testDiv(VR(42), VR(-5, 7), isSigned!T ? VR(-42, 42) : VR(0, 42));
		testDiv(VR(-47, 42), VR(-5, 7), isSigned!T ? VR(-47, 47) : VR());

		// degenerate numerator.
		testDiv(VR(2, 1), VR(89351496, 458963274),
		        VR(T.min / 89351496, T.max / 89351496));
		testDiv(VR(125, -23), VR(89351496, 458963274),
		        VR(T.min / 89351496, T.max / 89351496));
		testDiv(VR(-12, -23), VR(89351496, 458963274),
		        VR(T.min / 89351496, T.max / 89351496));

		/**
		 * Test rem
		 */
		// non overflowing
		testRem(VR(14, 52), VR(101, 109), VR(14, 52));
		testRem(VR(18, 47), VR(9, 109), VR(0, 47));
		testRem(VR(-21, 16), VR(123, 456),
		        isSigned!T ? VR(-21, 16) : VR(0, 455));

		// within the same loop
		testRem(VR(23), VR(5), VR(3));
		testRem(VR(127), VR(121, 123), VR(4, 6));
		testRem(VR(127, 132), VR(121, 125), VR(2, 11));
		testRem(VR(144, 156), VR(136, 144), VR(0, 20));

		// not in the same loop
		testRem(VR(12, 61), VR(49), VR(0, 48));
		testRem(VR(23, 152), VR(50), VR(0, 49));
		testRem(VR(12, 61), VR(49, 124), VR(0, 61));
		testRem(VR(118, 152), VR(50, 57), VR(0, 56));

		// degenerate numerator
		testRem(VR(125, -23), VR(210, 214),
		        isSigned!T ? VR(-213, 213) : VR(0, 213));

		// modulo 0 elimination.
		testRem(VR(23), VR(0, 3), VR(0, 2));
		testRem(VR(121, 161), VR(-57, 52), isSigned!T ? VR(0, 56) : VR(0, 161));
		testRem(VR(-21, 34), VR(-17, 24),
		        isSigned!T ? VR(-21, 23) : VR(0, T.max - 1));
		testRem(VR(34, 53), VR(-41, 36), isSigned!T ? VR(0, 40) : VR(0, 53));
		testRem(VR(-25, 42), VR(-13, 75),
		        isSigned!T ? VR(-25, 42) : VR(0, T.max - 1));

		/**
		 * Test left shift
		 */
		testLShift(VR(42), VR(0), VR(42));
		testLShift(VR(23), VR(2), VR(92));
		testLShift(VR(13), VR(0, 2), VR(13, 52));
		testLShift(VR(3, 13), VR(1, 7), VR(6, 1664));
		testLShift(VR(-30, -18), VR(1, 7), VR(-3840, -36));
		testLShift(VR(-5, 18), VR(1, 7), VR(-640, 2304));

		// full ranges and zeros
		testLShift(VR(0), VR(0), VR(0));
		testLShift(VR(0), VR(), VR(0));
		testLShift(VR(), VR(0), VR());
		testLShift(VR(), VR(), VR());

		// overflowing rhs
		testLShift(VR(5), VR(32), VR(LS ? 5UL << 32 : 0, 5UL << 32));
		testLShift(VR(5), VR(64), VR());
		testLShift(VR(5), VR(78), VR());
		testLShift(VR(5), VR(-1), VR());
		testLShift(VR(5), VR(-1, 7), VR());

		// oveflow lhs
		testLShift(VR(-1084, 1084), VR(21), VR(-1084UL << 21, 1084UL << 21));

		// degenerate ranges
		testLShift(VR(23, 6), VR(0), VR(23, 6));
		testLShift(VR(23, 6), VR(1), VR());
		testLShift(VR(23, -6), VR(0, 2), VR());
		testLShift(VR(-23, -62), VR(0, 2), VR());

		/**
		 * Test signed right shift
		 */
		testSRShift(VR(42), VR(0), VR(42));
		testSRShift(VR(42), VR(2), VR(10));
		testSRShift(VR(4321), VR(2, 7), VR(33, 1080));
		testSRShift(VR(12, 65), VR(1, 3), VR(1, 32));

		// Signed shift
		testSRShift(
			VR(-35, -22), VR(1, 3),
			isSigned!T ? VR(-18, -3) : VR((umin - 35) >> 3, (umin - 22) >> 1));
		testSRShift(VR(-35, 22), VR(0, 3),
		            isSigned!T ? VR(-35, 22) : VR((umin - 35) >> 3, 22));
		testSRShift(VR(-35, 22), VR(1, 3),
		            isSigned!T ? VR(-18, 11) : VR(0, umax >> 1));

		// full ranges and zeros
		testSRShift(VR(0), VR(0), VR(0));
		testSRShift(VR(0), VR(), VR(0));
		testSRShift(VR(), VR(0), VR());
		testSRShift(VR(), VR(), VR());

		// degenerate ranges
		testSRShift(VR(23, 6), VR(0), VR(23, 6));
		testSRShift(VR(23, 6), VR(1),
		            isSigned!T ? VR(11, 3) : VR(0, umax >> 1));
		testSRShift(VR(23, -6), VR(0, 2), isSigned!T ? VR(5, -2) : VR(5, -6));
		testSRShift(VR(23, -6), VR(1, 2),
		            isSigned!T ? VR(5, -2) : VR(5, (umin - 6) >> 1));
		testSRShift(VR(-23, -62), VR(0, 2), VR());

		/**
		 * Test unsigned right shift
		 */
		testURShift(VR(42), VR(0), VR(42));
		testURShift(VR(42), VR(2), VR(10));
		testURShift(VR(4321), VR(2, 7), VR(33, 1080));
		testURShift(VR(12, 65), VR(1, 3), VR(1, 32));

		// Signed shift
		testURShift(VR(-35, -22), VR(1, 3),
		            VR((umin - 35) >> 3, (umin - 22) >> 1));
		testURShift(VR(-35, 22), VR(0, 3), VR((umin - 35) >> 3, 22));
		testURShift(VR(-35, 22), VR(1, 3), VR(0, umax >> 1));

		// full ranges and zeros
		testURShift(VR(0), VR(0), VR(0));
		testURShift(VR(0), VR(), VR(0));
		testURShift(VR(), VR(0), VR());
		testURShift(VR(), VR(), VR());

		// degenerate ranges
		testURShift(VR(23, 6), VR(0), VR(23, 6));
		testURShift(VR(23, 6), VR(1), VR(0, umax >> 1));
		testURShift(VR(23, -6), VR(0, 2), VR(5, -6));
		testURShift(VR(23, -6), VR(2, 4), VR(1, (umin - 6) >> 2));
		testURShift(VR(-23, -62), VR(0, 2), VR());
		testURShift(VR(-23, -62), VR(1, 2), VR(0, umax >> 1));

		/**
		 * Test and
		 */
		testAnd(VR(123), VR(1), VR(1));
		testAnd(VR(11, 15), VR(1), VR(0, 1));
		testAnd(VR(11, 15), VR(2), VR(0, 2));
		testAnd(VR(10, 11), VR(2), VR(2, 2));
		testAnd(VR(10, 11), VR(3), VR(2, 3));
		testAnd(VR(9, 11), VR(3), VR(1, 3));
		testAnd(VR(10, 12), VR(3), VR(0, 3));
		testAnd(VR(21, 138), VR(0, 6), VR(0, 6));

		// Zero always gives 0
		testAnd(VR(0), VR(0), VR(0));
		testAnd(VR(123), VR(0), VR(0));
		testAnd(VR(123, 456), VR(0), VR(0));
		testAnd(VR(-5, 12), VR(0), VR(0));
		testAnd(VR(5, -12), VR(0), VR(0));

		// -1 Does nothing
		testAnd(VR(), VR(-1), VR());
		testAnd(VR(123), VR(-1), VR(123));
		testAnd(VR(123, 456), VR(-1), VR(123, 456));
		testAnd(VR(-123, 456), VR(-1), VR(-123, 456));
		// testAnd(VR(123, -456), VR(-1), VR(123, -456));

		// Full range extend to 0
		testAnd(VR(), VR(), VR());
		testAnd(VR(123), VR(), VR(0, 123));
		testAnd(VR(123, 456), VR(), VR(0, 456));
		testAnd(VR(-123, 456), VR(), VR());

		// Signed range
		testAnd(VR(-123, 456), VR(-1, 0), VR(-123, 456));
		testAnd(VR(-123, 456), VR(-1, 3), VR(-123, 456));
		testAnd(VR(-123, 456), VR(-2, 0), VR(-124, 456));

		/**
		 * Test or
		 */
		testOr(VR(), VR(), VR());
		testOr(VR(0), VR(0), VR(0));
		testOr(VR(1), VR(2), VR(3));
		testOr(VR(10, 12), VR(2), VR(10, 14));
		testOr(VR(10, 12), VR(3), VR(11, 15));

		// Zero does nothing
		testOr(VR(0), VR(0), VR(0));
		testOr(VR(123), VR(0), VR(123));
		testOr(VR(-5, 12), VR(0), VR(-5, 12));
		// testOr(VR(5, -12), VR(0), VR(5, -12));

		// -1 always gives -1
		testOr(VR(), VR(-1), VR(-1));
		testOr(VR(123), VR(-1), VR(-1));
		testOr(VR(123, 456), VR(-1), VR(-1));
		testOr(VR(-123, 456), VR(-1), VR(-1));
		testOr(VR(123, -456), VR(-1), VR(-1));

		// Full range extends to -1
		testOr(VR(), VR(), VR());
		testOr(VR(123), VR(), VR(123, -1));
		testOr(VR(123, 456), VR(), VR(123, -1));
		testOr(VR(-123, 456), VR(), VR());

		// Signed range
		testOr(VR(-123, 456), VR(-1, 0), VR(-123, 456));
		testOr(VR(-123, 456), VR(-1, 3), VR(-123, 459));
		testOr(VR(-123, 456), VR(1, 2), VR(-123, 458));

		/**
		 * Test xor
		 */
		// To be 100% honest, I'm not sure what are good test cases for xor.
		testXor(VR(), VR(), VR());
		testXor(VR(0), VR(0), VR(0));
		testXor(VR(1), VR(2), VR(3));
		testXor(VR(1), VR(3), VR(2));
		testXor(VR(123), VR(123), VR(0));
		testXor(VR(123), VR(123, 124), VR(0, 7));
		testXor(VR(3), VR(2, 3), VR(0, 1));
	}
}
