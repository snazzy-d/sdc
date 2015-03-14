module d.semantic.vrp;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.semantic.semantic;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct ValueRangePropagator {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	bool canFit(Expression e, Type t) {
		auto er = visit(e);
		auto tr = pessimise(t);
		
		auto sr = (tr.min > tr.max)
			? tr
			: ValueRange(~(tr.max / 2), tr.max / 2);
		
		if (er.min > er.max) {
			return er.min >= sr.min && er.max <= sr.max;
		}
		
		// Both negative.
		if (er.min >= sr.min) {
			return true;
		}
		
		auto ur = (tr.min > tr.max)
			? ValueRange(0, tr.max - tr.min)
			: tr;
		
		return er.min >= ur.min && er.max <= ur.max;
	}
	
	// Expressions
	ValueRange visit(Expression e) in {
		assert(e.type.kind == TypeKind.Builtin && canConvertToIntegral(e.type.builtin), "VRP expect integral types.");
	} out(result) {
		assert(result == result.recast(getBuiltin(e.type)), "Result is not casted properly.");
	} body {
		return this.dispatch(e);
	}
	
	ValueRange visit(BooleanLiteral e) {
		return ValueRange(e.value);
	}
	
	ValueRange visit(IntegerLiteral!false e) {
		return ValueRange(e.value).repack(e.type.builtin);
	}
	
	ValueRange visit(IntegerLiteral!true e) {
		return ValueRange(e.value).repack(e.type.builtin);
	}
	
	ValueRange visit(BinaryExpression e) {
		switch (e.op) with(BinaryOp) {
			case Comma, Assign :
				return visit(e.rhs);
			
			case Add :
				return add(visit(e.lhs), visit(e.rhs), e.type.builtin).recast(e.type.builtin);
			
			case Sub :
				// Get the complement and compute as an add.
				return sub(visit(e.lhs), visit(e.rhs), e.type.builtin).recast(e.type.builtin);
			
			case Concat :
				assert(0);
			
			case Mul :
				return mul(visit(e.lhs), visit(e.rhs), e.type.builtin).recast(e.type.builtin);
			
			case Div :
				auto rhs = visit(e.rhs);
				
				// We do an early check for divide by 0 so we don't need to visit lhs.
				if (rhs.hasZero) {
					return ValueRange.get(e.type.builtin);
				}
				
				return div(visit(e.lhs), rhs, e.type.builtin).recast(e.type.builtin);
			
			case Mod :
				return mod(visit(e.lhs), visit(e.rhs), e.type.builtin).recast(e.type.builtin);
			
			default :
				assert(0, "Not implemented.");
		}
	}
	
	ValueRange visit(UnaryExpression e) {
		assert(0, "Not implemented.");
	}
	
	ValueRange visit(VariableExpression e) {
		auto v = e.var;
		scheduler.require(v, Step.Processed);
		
		return (v.storage == Storage.Enum || v.type.qualifier == TypeQualifier.Immutable)
			? visit(v.value)
			: pessimise(v.type);
	}
	
	ValueRange visit(CastExpression e) {
		final switch (e.kind) with(CastKind) {
			case Invalid :
				assert(0, "Invalid cast");
			
			case IntToPtr, Down :
				assert(0, "Do not make any sense on integrals");
			
			case PtrToInt :
				return ValueRange.get(e.type.builtin);
			
			case IntToBool :
				return (visit(e.expr) == ValueRange(0))
					? ValueRange(0)
					: ValueRange(0, 1);
			
			case Trunc, Bit :
				return visit(e.expr)
					.repack(e.type.builtin)
					.recast(e.type.builtin);
			
			case SPad, UPad :
				return visit(e.expr).repack(e.type.builtin);
			
			case Qual, Exact :
				return visit(e.expr).recast(e.type.builtin);
		}
	}
	
private:
	auto add(ValueRange lhs, ValueRange rhs, BuiltinType t) {
		auto lrange = lhs.range;
		auto rrange = rhs.range;
		
		// If the total range overflow, pessimise.
		auto range = lrange + rrange;
		return (range < lrange && range < rrange)
			? ValueRange.get(t)
			: ValueRange(lhs.min + rhs.min, lhs.max + rhs.max).repack(t);
	}
	
	auto sub(ValueRange lhs, ValueRange rhs, BuiltinType t) {
		return add(lhs, rhs.complement(t), t);
	}
	
	auto getMulOverflow(ulong a, ulong b) {
		// (a0 << 32 + a1)(b0 << 32 + b1) = a0b0 << 64 + (a0b1 + a1b0) << 32 + a1b1
		auto a0 = a >> 32;
		auto a1 = a & uint.max;
		
		auto b0 = b >> 32;
		auto b1 = b & uint.max;
		
		auto a0b0 = a0 * b0;
		auto a0b1 = a0 * b1;
		auto a1b0 = a1 * b0;
		auto a1b1 = a1 * b1;
		
		auto carry = (a1b1 >> 32 + ((a0b1 + a1b0) & uint.max)) >> 32;
		return a0b0 + (a0b1 >> 32) + (a1b0 >> 32) + carry;
	}
	
	auto umul(ValueRange lhs, ValueRange rhs, BuiltinType t) in {
		assert(lhs.min <= lhs.max && rhs.min <= rhs.max);
	} body {
		// If a range is completely in the negtive, we take the complement as to avoid overflow.
		auto smax = getMask(t) >> 1;
		auto lneg = lhs.min > smax;
		if (lneg) {
			lhs = lhs.complement(t);
		}
		
		auto rneg = rhs.min > smax;
		if (rneg) {
			rhs = rhs.complement(t);
		}
		
		auto res = ValueRange(lhs.min * rhs.min, lhs.max * rhs.max);
		auto minoverflow = getMulOverflow(lhs.min, rhs.min);
		auto maxoverflow = getMulOverflow(lhs.max, rhs.max);
		
		// If one overflow, but not the other, we need to pessimize.
		if (minoverflow != maxoverflow) {
			return ValueRange.get(t);
		}
		
		// If we used the complement in only one case, take the complement of the result.
		return (lneg ^ rneg)
			? res.complement(t)
			: res.repack(t);
	}
	
	auto smul(ValueRange lhs, ValueRange rhs, BuiltinType t) in {
		assert(lhs.min > lhs.max && lhs.max != 0);
		assert(rhs != ValueRange(0));
	} body {
		// Make the computation in signed mode, so aggregation is easier.
		if (!isSigned(t)) {
			t = signed(t);
			lhs = lhs.repack(t);
			rhs = rhs.repack(t);
		}
		
		auto v0 = mul(ValueRange(0, lhs.max), rhs, t);
		
		// This is caused by [a, 0] or rhs = 0 and should be already handled.
		assert (v0.min != 0 || v0.max != 0);
		
		// If one or the other overflowed, propagate.
		if (v0.full) {
			return v0;
		}
		
		auto v1 = mul(ValueRange(lhs.min, 0), rhs, t);
		if (v1.full) {
			return v1;
		}
		
		// If rhs is positive, 0 must be kept in min.
		if (v0.min == 0 || v1.max == 0) {
			return ValueRange(v1.min, v0.max);
		}
		
		// If rhs is negative, 0 will be found in max.
		if (v0.max == 0 || v1.min == 0) {
			// assert(v1.min == 0);
			return ValueRange(v0.min, v1.max);
		}
		
		// If rhs is signed, aggregate both signed results.
		import std.algorithm;
		auto min = min(v0.min, v1.min);
		auto max = max(v0.max, v1.max);
		
		return (min > max)
			? ValueRange(min, max)
			: ValueRange.get(t);
	}
	
	ValueRange mul(ValueRange lhs, ValueRange rhs, BuiltinType t) {
		// Multiplication by 0 is always 0.
		auto zero = ValueRange(0);
		if (rhs == zero || lhs == zero) {
			return zero;
		}
		
		if (lhs.min > lhs.max) {
			// [-a, 0] * x = -([0, a] * x)
			return lhs.max
				? smul(lhs, rhs, t).repack(t)
				: mul(lhs.complement(t), rhs, t).complement(t);
		}
		
		return (rhs.min > rhs.max)
			? mul(rhs, lhs, t)
			: umul(lhs, rhs, t);
	}
	
	auto udiv(ValueRange lhs, ValueRange rhs, BuiltinType t) in {
		assert(!isSigned(t), "t must be unsigned.");
		assert(!rhs.hasZero, "Cannot divide by 0.");
	} body {
		if (lhs.min > lhs.max || lhs.full) {
			lhs = ValueRange(0, -1);
		}
		
		return ValueRange(lhs.min / rhs.max, lhs.max / rhs.min).repack(t);
	}
	
	ValueRange sdiv(ValueRange lhs, ValueRange rhs, BuiltinType t) in {
		assert(isSigned(t), "t must be signed.");
		assert(!rhs.hasZero, "Cannot divide by 0.");
	} body {
		rhs = rhs.signExtend(t);
		if (rhs.min > long.max) {
			// Must be true if rhs.hasZero is false.
			assert(rhs.max >= rhs.min);
			
			// a / b = -(a / -b)
			return sdiv(lhs, rhs.complement(t), t).complement(t);
		}
		
		lhs = lhs.getSigned(t);
		
		// Assert that full range are properly transformed.
		assert(!lhs.full || lhs == ValueRange(long.min, long.max));
		
		long lmin = lhs.min;
		long lmax = lhs.max;
		long rmin = rhs.min;
		long rmax = rhs.max;
		
		auto min = lmin < 0
			? lmin / rmin
			: lmin / rmax;
		
		auto max = lmax < 0
			? lmax / rmax
			: lmax / rmin;
		
		return ValueRange(min, max).repack(t);
	}
	
	auto div(ValueRange lhs, ValueRange rhs, BuiltinType t) {
		// Division by 0 is an error, bailing out.
		if (rhs.hasZero) {
			return ValueRange.get(t);
		}
		
		return isSigned(t)
			? sdiv(lhs, rhs, t)
			: udiv(lhs, rhs, t);
	}
	
	ValueRange umod(ValueRange lhs, ValueRange rhs, BuiltinType t) in {
		assert(!isSigned(t), "t must be unsigned.");
	} body {
		if (lhs.min > lhs.max) {
			lhs = ValueRange(0, -1);
		}
		
		if (rhs.min > rhs.max) {
			rhs = ValueRange(0, -1);
		}
		
		// If the range of lhs is greater than rhs.max, pessimise.
		auto lrange = lhs.range;
		if (lrange >= rhs.max) {
			return ValueRange(0, rhs.max - 1).repack(t);
		}
		
		// If lhs is within the bound of rhs.
		if (lhs.max < rhs.max) {
			return ValueRange((lhs.max > rhs.min) ? 0 : lhs.min, lhs.max).repack(t);
		}
		
		auto lminrmaxloop = lhs.min / rhs.max;
		auto lmaxrmaxloop = lhs.max / rhs.max;
		
		// If we are goign around more than once, pessimise.
		if (lminrmaxloop != lmaxrmaxloop) {
			return ValueRange(0, rhs.max - 1).repack(t);
		}
		
		// Ignore ranges that contains 0 ?
		if (rhs.min == 0) {
			rhs.min = 1;
		}
		
		// If we are goign around more than once, again, pessimise.
		auto lminrminloop = lhs.min / rhs.min;
		auto lmaxrminloop = lhs.max / rhs.min;
		if (lminrminloop != lmaxrminloop || lminrminloop != lminrmaxloop) {
			return ValueRange(0, lminrmaxloop ? rhs.max - 1 : lhs.max).repack(t);
		}
		
		// At this point, we know that as rhs grow, the result will reduce.
		// and as lhs grow, the result will increase.
		return ValueRange(lhs.min % rhs.max, lhs.max % rhs.min).repack(t);
	}
	
	ValueRange smod(ValueRange lhs, ValueRange rhs, BuiltinType t) in {
		assert(isSigned(t), "t must be signed.");
	} body {
		// Compute RHS absolute value range, as a % b = a % -b
		rhs = rhs.getSigned(t);
		if (rhs.min > rhs.max) {
			import std.algorithm;
			rhs = ValueRange(0, max(-rhs.min, rhs.max));
		} else if (rhs.min > long.max) {
			rhs = rhs.complement(t);
		}
		
		lhs = lhs.getSigned(t);
		auto ut = unsigned(t);
		
		// If lhs is signed, compute negative and positive, then aggregate.
		if (lhs.min > lhs.max) {
			auto pos = umod(ValueRange(0, lhs.max), rhs, ut);
			if (pos.full) {
				return pos;
			}
			
			auto neg = umod(ValueRange(0, -lhs.min), rhs, ut);
			if (neg.full) {
				return neg;
			}
			
			auto min = -neg.max;
			auto max = pos.max;
			
			return min > max
				? ValueRange(min, max).repack(t)
				: ValueRange.get(t);
		}
		
		return lhs.min > long.max
			? umod(lhs.complement(t), rhs, ut).complement(t)
			: umod(lhs, rhs, ut).repack(t);
	}
	
	auto mod(ValueRange lhs, ValueRange rhs, BuiltinType t) {
		return isSigned(t)
			? smod(lhs, rhs, t)
			: umod(lhs, rhs, t);
	}
	
	BuiltinType getBuiltin(Type t) {
		if (t.kind == TypeKind.Enum) {
			scheduler.require(t.denum, Step.Signed);
			return getBuiltin(t.denum.type);
		}
		
		if (t.hasPointerABI()) {
			return getBuiltin(pass.object.getSizeT().type);
		}
		
		assert(t.kind == TypeKind.Builtin);
		assert(canConvertToIntegral(t.builtin), "Only integral are supported for now.");
		
		return t.builtin;
	}
	
	auto pessimise(Type t) {
		return ValueRange.get(getBuiltin(t));
	}
}

private:
struct ValueRange {
	ulong min = ulong.min;
	ulong max = ulong.max;
	
	this(ulong min, ulong max) {
		this.min = min;
		this.max = max;
	}
	
	this(ulong value) {
		this(value, value);
	}
	
	@property
	ulong range() const {
		return max - min;
	}
	
	@property
	bool full() const {
		return range == -1;
	}
	
	@property
	bool hasZero() const {
		return min == 0 || min > max;
	}
	
	auto complement(BuiltinType t) const {
		return ValueRange(-max, -min).repack(t);
	}
	
	auto recast(BuiltinType t) const in {
		assert(this == this.repack(t), "Not repacked properly.");
	} out(result) {
		assert(result.range <= getMask(t), "Produced result of invalid range.");
	} body {
		auto mask = getMask(t);
		auto signed = isIntegral(t) && isSigned(t);
		
		auto sign_max = mask >> 1;
		auto sign_min = sign_max | ~mask;
		auto sign_mask = sign_max + 1;
		
		if (min > max) {
			return (signed && min >= sign_min && max <= sign_max)
				? this
				: ValueRange(t);
		}
		
		if (max <= sign_max) {
			return this;
		}
		
		if (signed && min >= sign_min) {
			return this;
		}
		
		if (!signed && max <= mask) {
			return this;
		}
		
		return ValueRange.get(t);
	}
	
	auto repack(BuiltinType t) const out(result) {
		assert(result.range <= getMask(t), "Produced result of invalid range.");
	} body {
		auto mask = getMask(t);
		auto signed = isIntegral(t) && isSigned(t);
		
		auto sign_max = mask >> 1;
		auto sign_min = sign_max | ~mask;
		auto sign_mask = sign_max + 1;
		
		// If range excceed, then return the full range.
		if (range >= mask) {
			return signed
				? ValueRange(sign_mask | ~mask, sign_max)
				: ValueRange(0, mask);
		}
		
		auto smin = min | ~mask;
		auto smax = max | ~mask;
		auto umin = min & mask;
		auto umax = max & mask;
		
		if (min > max) {
			assert(min == smin && max == umax);
			return ValueRange(smin, umax);
		}
		
		// Ensure that truncation create a range that fit.
		if (umin > umax) {
			return ValueRange(smin, umax);
		}
		
		if (!signed) {
			return ValueRange(umin, umax);
		}
		
		// If this is signed, we sign extend if both are negative.
		return ((min & sign_mask) && (max & sign_mask))
			? ValueRange(smin, smax)
			: ValueRange(umin, umax);
	}
	
	bool opEquals(ValueRange rhs) const {
		return (full && rhs.full) || (min == rhs.min && max == rhs.max);
	}
	
	// FIXME, not sure, need sanity check.
	auto signExtend(BuiltinType t) const {
		auto mask = getMask(t);
		assert(range <= mask);
		
		auto sign_mask = (mask >> 1) + 1;
		return ValueRange(
			(min & sign_mask)
				? min | ~mask
				: min & mask,
			(max & sign_mask)
				? max | ~mask
				: max & mask,
		);
	}
	
	auto getSigned(BuiltinType t) const {
		auto res = signExtend(t);
		
		// Full range need to be adjusted for signed computation.
		if (res.min < long.min && res.max > long.max) {
			// [------min----/----max------]
			res = ValueRange(long.min, long.max);
		} else if (res.min > res.max && (res.max > long.max || res.min < long.min)) {
			// [--max-min----/------------] or [-------------/--max---min-]
			res = ValueRange(long.min, long.max);
		}
		
		return res;
	}
	
static:
	ValueRange get(BuiltinType t) in {
		assert(canConvertToIntegral(t));
	} body {
		auto mask = getMask(t);
		return (isIntegral(t) && isSigned(t))
			? ValueRange(((mask >> 1) + 1) | ~mask, mask >> 1)
			: ValueRange(0, mask);
	}
}


ulong getMask(BuiltinType t) in {
	assert(canConvertToIntegral(t));
} body {
	if (t == BuiltinType.Bool) {
		return 1;
	}
	
	t = isChar(t)
		? integralOfChar(t)
		: unsigned(t);
	
	return getMax(t);
}

unittest {
	auto v = ValueRange.get(BuiltinType.Bool);
	assert(v.min == bool.min);
	assert(v.max == bool.max);
	
	v = ValueRange.get(BuiltinType.Byte);
	assert(v.min == byte.min);
	assert(v.max == byte.max);
	
	v = ValueRange.get(BuiltinType.Char);
	assert(v.min == ubyte.min);
	assert(v.max == ubyte.max);
	
	v = ValueRange.get(BuiltinType.Ulong);
	assert(v.min == ulong.min);
	assert(v.max == ulong.max);
}

unittest {
	auto vrp = ValueRangePropagator();
	
	import d.location;
	auto v = vrp.visit(new BooleanLiteral(Location.init, false));
	assert(v.min == false);
	assert(v.max == false);
	
	v = vrp.visit(new BooleanLiteral(Location.init, true));
	assert(v.min == true);
	assert(v.max == true);
	
	v = vrp.visit(new IntegerLiteral!true(Location.init, -9, BuiltinType.Byte));
	assert(v.min == -9);
	assert(v.max == -9);
	
	v = vrp.visit(new IntegerLiteral!false(Location.init, 42, BuiltinType.Uint));
	assert(v.min == 42);
	assert(v.max == 42);
}

unittest {
	auto vrp = ValueRangePropagator();
	
	import d.location;
	auto i1 = new IntegerLiteral!true(Location.init, -9, BuiltinType.Int);
	auto i2 = new IntegerLiteral!true(Location.init, 42, BuiltinType.Int);
	
	auto v = vrp.visit(new BinaryExpression(Location.init, Type.get(BuiltinType.Int), BinaryOp.Comma, i1, i2));
	assert(v == ValueRange(42));
	
	// Technically, this is illegal, but it is out of scope of VRP to detect this, so will do.
	v = vrp.visit(new BinaryExpression(Location.init, Type.get(BuiltinType.Int), BinaryOp.Assign, i1, i2));
	assert(v == ValueRange(42));
	
	v = vrp.visit(new BinaryExpression(Location.init, Type.get(BuiltinType.Int), BinaryOp.Add, i1, i2));
	assert(v == ValueRange(33));
	
	v = vrp.visit(new BinaryExpression(Location.init, Type.get(BuiltinType.Int), BinaryOp.Sub, i1, i2));
	assert(v == ValueRange(-51));
	
	v = vrp.visit(new BinaryExpression(Location.init, Type.get(BuiltinType.Int), BinaryOp.Mul, i1, i2));
	assert(v == ValueRange(-378));
	
	v = vrp.visit(new BinaryExpression(Location.init, Type.get(BuiltinType.Int), BinaryOp.Div, i2, i1));
	assert(v == ValueRange(-4));
	
	v = vrp.visit(new BinaryExpression(Location.init, Type.get(BuiltinType.Int), BinaryOp.Mod, i2, i1));
	assert(v == ValueRange(6));
}

unittest {
	auto vrp = ValueRangePropagator();
	
	import d.location;
	auto i = new IntegerLiteral!false(Location.init, cast(uint) -6, BuiltinType.Uint);
	
	auto v = vrp.visit(new CastExpression(Location.init, CastKind.Bit, Type.get(BuiltinType.Ubyte), i));
	assert(v == ValueRange(250));
	
	v = vrp.visit(new CastExpression(Location.init, CastKind.UPad, Type.get(BuiltinType.Ulong), i));
	assert(v == ValueRange(cast(uint) -6));
}

unittest {
	auto vrp = ValueRangePropagator();
	
	foreach(t; BuiltinType.Byte .. BuiltinType.Cent) {
		void testAdd(ValueRange lhs, ValueRange rhs, ValueRange res) {
			auto clhs = lhs.complement(t);
			auto crhs = rhs.complement(t);
			auto cres = res.complement(t);
			
			lhs = lhs.repack(t);
			rhs = rhs.repack(t);
			res = res.repack(t);
			
			auto v = vrp.add(lhs, rhs, t);
			assert(v == res, "a + b");
			
			v = vrp.add(rhs, lhs, t);
			assert(v == res, "a + b = b + a");
			
			v = vrp.add(clhs, crhs, t);
			assert(v == cres, "-a + -b = -(a + b)");
		}
		
		testAdd(ValueRange(1), ValueRange(-1), ValueRange(0));
		testAdd(ValueRange(-5, 0), ValueRange(-1, 5), ValueRange(-6, 5));
		testAdd(ValueRange(5, 6), ValueRange(-3, 5), ValueRange(2, 11));
		testAdd(ValueRange(-12, 85), ValueRange(5, 53), ValueRange(-7, 138));
		testAdd(ValueRange(1, long.max), ValueRange(long.min, -1), ValueRange(1 + long.min, long.max - 1));
		
		// overflow
		testAdd(ValueRange(0, -42), ValueRange(42, -1), ValueRange(0, -1));
		testAdd(ValueRange(1, long.max + 2), ValueRange(long.min, -1), ValueRange(0, -1));
		
		void testSub(ValueRange lhs, ValueRange rhs, ValueRange res) {
			auto clhs = lhs.complement(t);
			auto crhs = rhs.complement(t);
			auto cres = res.complement(t);
			
			lhs = lhs.repack(t);
			rhs = rhs.repack(t);
			res = res.repack(t);
			
			auto v = vrp.sub(lhs, rhs, t);
			assert(v == res, "a - b");
			
			v = vrp.sub(rhs, lhs, t);
			assert(v == cres, "b - a = -(a - b)");
			
			v = vrp.add(lhs, crhs, t);
			assert(v == res, "a + -b = a - b");
			
			v = vrp.sub(clhs, crhs, t);
			assert(v == cres, "-a - -b = -(a - b)");
		}
		
		testSub(ValueRange(-1), ValueRange(1), ValueRange(-2));
		
		void testMul(ValueRange lhs, ValueRange rhs, ValueRange res) {
			auto clhs = lhs.complement(t);
			auto crhs = rhs.complement(t);
			auto cres = res.complement(t);
			
			lhs = lhs.repack(t);
			rhs = rhs.repack(t);
			res = res.repack(t);
			
			auto v = vrp.mul(lhs, rhs, t);
			assert(v == res, "ab");
			
			v = vrp.mul(rhs, lhs, t);
			assert(v == res, "ab = ba");
			
			v = vrp.mul(clhs, rhs, t);
			assert(v == cres, "(-a) * b = -ab");
			
			v = vrp.mul(lhs, crhs, t);
			assert(v == cres, "a * (-b) = -ab");
			
			v = vrp.mul(clhs, crhs, t);
			assert(v == res, "(-a) * (-b) = ab");
		}
		
		// min < max
		testMul(ValueRange(2, 3), ValueRange(0), ValueRange(0));
		testMul(ValueRange(2, 3), ValueRange(7, 23), ValueRange(14, 69));
		testMul(ValueRange(1), ValueRange(125, -32), ValueRange(125, -32));
		testMul(ValueRange(-7, -4), ValueRange(-5, -3), ValueRange(12, 35));
		testMul(ValueRange(3, 3037000500), ValueRange(7, 3037000500), ValueRange(21, 9223372037000250000UL));
		
		// min > max on one side
		testMul(ValueRange(-5, 42), ValueRange(1), ValueRange(-5, 42));
		testMul(ValueRange(-5, 42), ValueRange(2, 5), ValueRange(-25, 210));
		testMul(ValueRange(-5, 12), ValueRange(0, 7), ValueRange(-35, 84));
		testMul(ValueRange(-5, 42), ValueRange(0), ValueRange(0));
		testMul(ValueRange(5, 3037000500), ValueRange(-12, 3037000500), ValueRange(-36444006000, 9223372037000250000UL));
		
		// min > max on both side
		testMul(ValueRange(-1, 5), ValueRange(-7, 22), ValueRange(-35, 110));
		testMul(ValueRange(-11, 3037000500), ValueRange(-8, 3037000500), ValueRange(-33407005500, 9223372037000250000UL));
		
		// overflow
		testMul(ValueRange(123), ValueRange(long.min, ulong.max), ValueRange(0, -1));
		testMul(ValueRange(0, 4294967296), ValueRange(0, 4294967297), ValueRange(0, -1));
		testMul(ValueRange(-23, 4294967296), ValueRange(10, 4294967297), ValueRange(0, -1));
		testMul(ValueRange(-3037000500, 3037000500), ValueRange(-3037000500, 3037000500), ValueRange(0, -1));
	}
	
	void testUdiv(ValueRange lhs, ValueRange rhs, ValueRange res) {
		auto v = vrp.div(lhs, rhs, BuiltinType.Ulong);
		assert(v == res, "a / b");
	}
	
	// unsigned numerator.
	testUdiv(ValueRange(23), ValueRange(5), ValueRange(4));
	testUdiv(ValueRange(23, 125), ValueRange(5, 7), ValueRange(3, 25));
	testUdiv(ValueRange(0, 201), ValueRange(12, 17), ValueRange(0, 16));
	
	// division by 0.
	testUdiv(ValueRange(42), ValueRange(0), ValueRange(0, -1));
	testUdiv(ValueRange(42), ValueRange(-8, 0), ValueRange(0, -1));
	testUdiv(ValueRange(42), ValueRange(0, 25), ValueRange(0, -1));
	testUdiv(ValueRange(42), ValueRange(-5, 7), ValueRange(0, -1));
	
	// signed numerator.
	testUdiv(ValueRange(-23, 125), ValueRange(89351496, 458963274), ValueRange(0, 206451429461));
	
	// degenerate numerator.
	testUdiv(ValueRange(2, 1), ValueRange(89351496, 458963274), ValueRange(0, 206451429461));
	
	void testSdiv(ValueRange lhs, ValueRange rhs, ValueRange res) {
		auto t = BuiltinType.Long;
		
		auto clhs = lhs.complement(t);
		auto crhs = rhs.complement(t);
		auto cres = res.complement(t);
		
		auto v = vrp.div(lhs, rhs, t);
		assert(v == res, "a / b");
		
		v = vrp.div(clhs, rhs, t);
		assert(v == cres, "(-a) / b = -(a / b)");
		
		v = vrp.div(lhs, crhs, t);
		assert(v == cres, "a / (-b) = -(a / b)");
		
		v = vrp.div(clhs, crhs, t);
		assert(v == res, "(-a) / (-b) = a / b");
	}
	
	// signed numerator.
	testSdiv(ValueRange(23), ValueRange(5), ValueRange(4));
	testSdiv(ValueRange(23, 42), ValueRange(5), ValueRange(4, 8));
	testSdiv(ValueRange(0, 37), ValueRange(2, 7), ValueRange(0, 18));
	testSdiv(ValueRange(14, 122), ValueRange(3, 6), ValueRange(2, 40));
	testSdiv(ValueRange(-27, 31), ValueRange(5, 9), ValueRange(-5, 6));
	
	// division by 0.
	testSdiv(ValueRange(42), ValueRange(0), ValueRange(0, -1));
	testSdiv(ValueRange(42), ValueRange(-8, 0), ValueRange(0, -1));
	testSdiv(ValueRange(42), ValueRange(0, 25), ValueRange(0, -1));
	testSdiv(ValueRange(42), ValueRange(-5, 7), ValueRange(0, -1));
	
	// degenerate numerator.
	testSdiv(ValueRange(125, -23), ValueRange(89351496, 458963274), ValueRange(-103225714730, 103225714730));
	testSdiv(ValueRange(221, 47), ValueRange(89351496, 458963274), ValueRange(-103225714730, 103225714730));
	testSdiv(ValueRange(-12, -23), ValueRange(89351496, 458963274), ValueRange(-103225714730, 103225714730));
	
	void testUmod(ValueRange lhs, ValueRange rhs, ValueRange res) {
		auto v = vrp.mod(lhs, rhs, BuiltinType.Ulong);
		assert(v == res, "a % b");
	}
	
	// non overflowing results.
	testUmod(ValueRange(14, 52), ValueRange(101, 109), ValueRange(14, 52));
	testUmod(ValueRange(18, 47), ValueRange(9, 109), ValueRange(0, 47));
	
	// within range.
	testUmod(ValueRange(23), ValueRange(5), ValueRange(3));
	testUmod(ValueRange(127), ValueRange(121, 123), ValueRange(4, 6));
	testUmod(ValueRange(127, 132), ValueRange(121, 125), ValueRange(2, 11));
	testUmod(ValueRange(144, 156), ValueRange(136, 144), ValueRange(0, 20));
	
	// rhs overflow.
	testUmod(ValueRange(12, 61), ValueRange(49), ValueRange(0, 48));
	testUmod(ValueRange(23, 152), ValueRange(50), ValueRange(0, 49));
	testUmod(ValueRange(12, 61), ValueRange(49, 124), ValueRange(0, 61));
	testUmod(ValueRange(118, 152), ValueRange(50, 57), ValueRange(0, 56));
	
	// modulo 0 elimination.
	testUmod(ValueRange(23), ValueRange(0, 3), ValueRange(0, 2));
	
	// oveflow
	testUmod(ValueRange(-21, 16), ValueRange(123, 456), ValueRange(0, 455));
	testUmod(ValueRange(34, 53), ValueRange(-41, 36), ValueRange(0, 53));
	testUmod(ValueRange(-25, 42), ValueRange(-13, 75), ValueRange(0, -2));
	
	void testSmod(ValueRange lhs, ValueRange rhs, ValueRange res) {
		auto t = BuiltinType.Long;
		
		auto clhs = lhs.complement(t);
		auto crhs = rhs.complement(t);
		auto cres = res.complement(t);
		
		auto v = vrp.mod(lhs, rhs, t);
		assert(v == res, "a % b");
		
		v = vrp.mod(lhs, crhs, t);
		assert(v == res, "a % -b = a % b");
		
		v = vrp.mod(clhs, rhs, t);
		assert(v == cres, "-a % b = -(a % b)");
		
		v = vrp.mod(clhs, crhs, t);
		assert(v == cres, "-a % -b = -(a % b)");
	}
	
	// test various signed ranges.
	testSmod(ValueRange(23), ValueRange(5), ValueRange(3));
	testSmod(ValueRange(121, 161), ValueRange(-57, 52), ValueRange(0, 56));
	testSmod(ValueRange(-21, 34), ValueRange(-17, 24), ValueRange(-21, 23));
	
	// degenerate numerator.
	testSmod(ValueRange(125, -23), ValueRange(210, 214), ValueRange(-213, 213));
	testSmod(ValueRange(221, 47), ValueRange(-45, 13), ValueRange(-44, 44));
	testSmod(ValueRange(-12, -23), ValueRange(-25, 132), ValueRange(-131, 131));
	
	// degenerate denumerator.
	testSmod(ValueRange(-21, 16), ValueRange(456, 123), ValueRange(-21, 16));
	testSmod(ValueRange(34, 53), ValueRange(-32, -41), ValueRange(0, 53));
	testSmod(ValueRange(42, -25), ValueRange(75, -13), ValueRange(long.min + 1, long.max));
}

