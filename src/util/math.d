module util.math;

import std.traits;

bool isPow2(T)(T x) if (isIntegral!T) {
	return (x & (x - 1)) == 0;
}

Signed!T maybeNegate(T)(T value, bool neg) {
	return (value - neg) ^ -neg;
}

unittest {
	foreach (ulong i; 0 .. 64) {
		assert(maybeNegate(i, false) == i);
		assert(maybeNegate(i, true) == -i);
		assert(maybeNegate(-i, false) == -i);
		assert(maybeNegate(-i, true) == i);
	}
}

uint countLeadingZeros(T)(T x) if (isIntegral!T) in(x != 0) {
	import core.bitop;
	return (8 * T.sizeof - 1 - bsr(x)) & uint.max;
}

unittest {
	foreach (i; 0 .. 64) {
		assert(countLeadingZeros(-1UL >> i) == i);
		assert(countLeadingZeros(0x8000000000000000 >> i) == i);
		assert(countLeadingZeros(0xe0b62e2929aba83c >> i) == i);
	}
}

uint countTrailingZeros(T)(T x) if (isIntegral!T) in(x != 0) {
	import core.bitop;
	return bsf(x) & uint.max;
}

unittest {
	foreach (i; 0 .. 64) {
		assert(countTrailingZeros(1UL << i) == i);
		assert(countTrailingZeros(5UL << i) == i);
		assert(countTrailingZeros(-1UL << i) == i);
	}
}

version(LDC) {
	// Due to a frontend bug, importing ldc.llvmasm sometime leads
	// to linker errors, so we declare it manually.
	pragma(LDC_inline_ir)
	R __ir(string s, R, P...)(P params) @trusted nothrow @nogc;
}

// I have not figured out how to do this in a sensible way.
// See: https://forum.dlang.org/post/zsaghidvbsdwqthadphx@forum.dlang.org
ulong mulhi()(ulong a, ulong b) {
	version(LDC) {
		return __ir!(`
			%a = zext i64 %0 to i128
			%b = zext i64 %1 to i128
			%r = mul i128 %a, %b
			%r2 = lshr i128 %r, 64
			%r3 = trunc i128 %r2 to i64
			ret i64 %r3`, ulong)(a, b);
	} else {
		// (a0 << 32 + a1)(b0 << 32 + b1) = a0b0 << 64 + (a0b1 + a1b0) << 32 + a1b1
		auto a0 = a >> 32;
		auto a1 = a & uint.max;

		auto b0 = b >> 32;
		auto b1 = b & uint.max;

		auto a0b0 = a0 * b0;
		auto a0b1 = a0 * b1;
		auto a1b0 = a1 * b0;
		auto a1b1 = a1 * b1;

		auto lo = (a1b1 >> 32) + (a0b1 & uint.max) + (a1b0 & uint.max);
		return a0b0 + (a0b1 >> 32) + (a1b0 >> 32) + (lo >> 32);
	}
}

unittest {
	assert(mulhi(0, 0) == 0);
	assert(mulhi(0xcde6fd5e09abcf26, 0x0b6dfb9c0f956447) == 0x0931629beb2ac9c8);
	assert(mulhi(0xa8acd7c0222311bc, 0xf50a3fa490c30190) == 0xa1742b2a45611ae0);
	assert(mulhi(0x5cafb867790ea400, 0x775ea264cf55347e) == 0x2b37f20981aab417);
	assert(mulhi(0xcecb8f27f4200f3a, 0x9e74d1b791e07e48) == 0x7fffffffffffffff);
	assert(mulhi(0x7fffffffffffffff, 0x7fffffffffffffff) == 0x3fffffffffffffff);
	assert(mulhi(0xffffffffffffffff, 0xffffffffffffffff) == 0xfffffffffffffffe);
}
