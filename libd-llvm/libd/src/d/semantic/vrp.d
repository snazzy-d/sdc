module d.semantic.vrp;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.semantic.semantic;

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
	bool full() const {
		return (min - max) == 1;
	}
	
	auto complement(Type t) const {
		return ValueRange(-max, -min).repack(t);
	}
	
	auto repack(Type t) const {
		auto mask = getMask(t);
		
		// If overflow is identical, then simply strip it.
		return ((min & ~mask) == (max & ~mask))
			? ValueRange(min & mask, max & mask)
			: ValueRange(0, mask);
	}
	
	bool opEquals(ValueRange rhs) const {
		return (full && rhs.full) || (min == rhs.min && max == rhs.max);
	}
	
static:
	ValueRange get(ulong u0, ulong u1, ulong u2, ulong u3) {
		import std.algorithm;
		return ValueRange(min(u0, u1, u2, u3), max(u0, u1, u2, u3));
	}
	
	ValueRange get(Type t) {
		return ValueRange(0, getMask(t));
	}
	
	ulong getMask(Type t) {
		if (t.kind == TypeKind.Enum) {
			return getMask(t.denum.type);
		}
		
		if (t.hasPointerABI()) {
			return ulong.max;
		}
		
		auto bt = t.builtin;
		assert(canConvertToIntegral(bt));
		
		if (bt == BuiltinType.Bool) {
			return 1;
		}
		
		bt = isChar(bt)
			? integralOfChar(bt)
			: unsigned(bt);
		
		return getMax(bt);
	}
}

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct ValueRangePropagator {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	bool canFit(Expression e, Type t) {
		auto ev = visit(e);
		auto tv = ValueRange.get(t);
		
		return ev.min >= tv.min && ev.max <= tv.max;
	}
	
	// Expressions
	ValueRange visit(Expression e) in {
		assert(e.type.kind == TypeKind.Builtin && isIntegral(e.type.builtin), "VRP expect integral types.");
	} body {
		return this.dispatch(e);
	}
	
	ValueRange visit(BooleanLiteral e) {
		return ValueRange(e.value);
	}
	
	ValueRange visit(IntegerLiteral!false e) {
		return ValueRange(e.value).repack(e.type);
	}
	
	ValueRange visit(IntegerLiteral!true e) {
		return ValueRange(e.value).repack(e.type);
	}
	
	private auto add(ValueRange lhs, ValueRange rhs, Type t) {
		auto lrange = lhs.max - lhs.min;
		auto rrange = rhs.max - rhs.min;
		
		// If the total range overflow, pessimise.
		auto range = lrange + rrange;
		return (range < lrange && range < rrange)
			? ValueRange.get(t)
			: ValueRange(lhs.min + rhs.min, lhs.max + rhs.max).repack(t);
	}
	
	private auto sub(ValueRange lhs, ValueRange rhs, Type t) {
		return add(lhs, rhs.complement(t), t);
	}
	
	private auto getMulOverflow(ulong a, ulong b) {
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
	
	private ValueRange mul(ValueRange lhs, ValueRange rhs, Type t) {
		if (lhs.min > lhs.max) {
			// [a, 0] * x = -([0, -a] * x)
			if (lhs.max == 0) {
				return mul(lhs.complement(t), rhs, t).complement(t);
			}
			
			auto v0 = mul(ValueRange(0, lhs.max), rhs, t);
			auto v1 = mul(ValueRange(lhs.min, -1), rhs, t);
			
			// This is caused by [a, 0] case and should be already handled.
			assert (v0.min != 0 || v0.max != 0);
			
			// If one or the other overflowed, propagate.
			if (v0.full) {
				return v0;
			}
			
			if (v1.full) {
				return v1;
			}
			
			// If rhs is positive, 0 must be kept in min.
			if (v0.min == 0) {
				return ValueRange(v1.min, v0.max);
			}
			
			// If rhs is negative, 0 will be found in max.
			if (v0.max == 0) {
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
		
		if (rhs.min > rhs.max) {
			return mul(rhs, lhs, t);
		}
		
		// If a range is completely in the negtive, we take the complement as to avoid overflow.
		auto lneg = lhs.min > long.max;
		if (lneg) {
			lhs = lhs.complement(t);
		}
		
		auto rneg = rhs.min > long.max;
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
	
	ValueRange visit(BinaryExpression e) {
		switch (e.op) with(BinaryOp) {
			case Comma :
			case Assign :
				return visit(e.rhs).repack(e.type);
			
			case Add :
				return add(visit(e.lhs), visit(e.rhs), e.type);
			
			case Sub :
				// Get the complement and compute as an add.
				return sub(visit(e.lhs), visit(e.rhs), e.type);
			
			case Concat :
				assert(0);
			
			case Mul :
				return mul(visit(e.lhs), visit(e.rhs), e.type);
			
			case Div, Mod :
			
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
			: ValueRange.get(v.type);
	}
}

unittest {
	auto v = ValueRange.get(Type.get(BuiltinType.Bool));
	assert(v.min == bool.min);
	assert(v.max == bool.max);
	
	v = ValueRange.get(Type.get(BuiltinType.Byte));
	assert(v.min == ubyte.min);
	assert(v.max == ubyte.max);
	
	v = ValueRange.get(Type.get(BuiltinType.Char));
	assert(v.min == ubyte.min);
	assert(v.max == ubyte.max);
	
	v = ValueRange.get(Type.get(BuiltinType.Ulong));
	assert(v.min == ulong.min);
	assert(v.max == ulong.max);
	
	v = ValueRange.get(Type.get(BuiltinType.Void).getPointer());
	assert(v.min == ulong.min);
	assert(v.max == ulong.max);
	
	v = ValueRange.get(Type.get(Class.init));
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
	assert(v.min == cast(ubyte) -9);
	assert(v.max == cast(ubyte) -9);
	
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
	
	v = vrp.visit(new BinaryExpression(Location.init, Type.get(BuiltinType.Int), BinaryOp.Add, i1, i2));
	assert(v == ValueRange(33));
	
	v = vrp.visit(new BinaryExpression(Location.init, Type.get(BuiltinType.Int), BinaryOp.Sub, i1, i2));
	assert(v == ValueRange(cast(uint) -51));
	
	v = vrp.visit(new BinaryExpression(Location.init, Type.get(BuiltinType.Int), BinaryOp.Mul, i1, i2));
	assert(v == ValueRange(cast(uint) -378));
}

unittest {
	auto vrp = ValueRangePropagator();
	auto t = Type.get(BuiltinType.Long);
	
	void testAdd(ValueRange lhs, ValueRange rhs, ValueRange res) {
		auto v = vrp.add(lhs, rhs, t);
		assert(v == res, "a + b");
		
		v = vrp.add(rhs, lhs, t);
		assert(v == res, "a + b = b + a");
		
		v = vrp.add(lhs.complement(t), rhs.complement(t), t);
		assert(v == res.complement(t), "-a + -b = -(a + b)");
	}
	
	testAdd(ValueRange(1), ValueRange(-1), ValueRange(0));
	testAdd(ValueRange(-5, 0), ValueRange(-1, 5), ValueRange(-6, 5));
	testAdd(ValueRange(5, 6), ValueRange(-3, 5), ValueRange(2, 11));
	testAdd(ValueRange(-12, 85), ValueRange(5, 53), ValueRange(-7, 138));
	testAdd(ValueRange(0, -42), ValueRange(42, -1), ValueRange(0, -1));
	
	void testSub(ValueRange lhs, ValueRange rhs, ValueRange res) {
		auto v = vrp.sub(lhs, rhs, t);
		assert(v == res, "a - b");
		
		v = vrp.sub(rhs, lhs, t);
		assert(v == res.complement(t), "b - a = -(a - b)");
		
		v = vrp.add(lhs, rhs.complement(t), t);
		assert(v == res, "a + -b = a - b");
		
		v = vrp.sub(lhs.complement(t), rhs.complement(t), t);
		assert(v == res.complement(t), "-a - -b = -(a - b)");
	}
	
	testSub(ValueRange(-1), ValueRange(1), ValueRange(-2));
	
	void testMul(ValueRange lhs, ValueRange rhs, ValueRange res) {
		auto v = vrp.mul(lhs, rhs, t);
		assert(v == res, "ab");
		
		v = vrp.mul(rhs, lhs, t);
		assert(v == res, "ab = ba");
		
		v = vrp.mul(lhs.complement(t), rhs, t);
		assert(v == res.complement(t), "(-a) * b = -ab");
		
		v = vrp.mul(lhs, rhs.complement(t), t);
		assert(v == res.complement(t), "a * (-b) = -ab");
		
		v = vrp.mul(lhs.complement(t), rhs.complement(t), t);
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

